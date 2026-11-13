#!/usr/bin/env bash
# testar-i1-gpu.sh — teste individual do I1 na GPU da Jetson (TensorRT via P2), sem Kafka.
#
# Usa só o que vem no repositório do I1: o Dockerfile.jetson, o pacote B5 (ONNX + metadata.json)
# e as imagens de fixtures. Nada é publicado no Kafka: o I1 roda em --mode stdout, então a
# cadeia do A8 (I2, S1…) não recebe as detecções de teste.
#
#   ./testar-i1-gpu.sh               pacote app-plates/1.0.0 e as fixtures dele
#   ./testar-i1-gpu.sh --sem-cpu     pula a comparação com a CPU (ONNX Runtime)
#   ./testar-i1-gpu.sh --pacote app-epi/1.0.0 --imagens /pasta/com/fotos
#                                    outro pacote; sem --imagens, usa as fixtures de placas
#                                    (só prova a GPU, as detecções não significam nada)
#
# Lê I1_REF, SRC_DIR e I1_ENGINES_DIR de builds/a8/a8.env (troque com A8_ENV=<arquivo>).
# Constrói a imagem ods-i1-gpu:<I1_REF> se ela não existir (a mesma que o ./a8.sh usa) e
# compila a engine na primeira vez (minutos).
# Resultado: validacao/i1/resultados/i1-gpu-<data>.txt (+ .jsonl com as mensagens e logs).
#
# Itens:
#   G01 placa Jetson com runtime nvidia no Docker      G05 I1 roda nas fixtures e termina com 0
#   G02 imagem com TensorRT e P2 (backend trt)         G06 uma mensagem válida por imagem
#   G03 engine compilada e carregando (FP16)           G07 artifact_version = engine (…-fp16)
#   G04 inferência na GPU: libnvinfer carregada,       G08 detecções nas fixtures (classes do pacote)
#       GR3D_FREQ > 0% no tegrastats                   G09 comparação com a CPU (informativo)
set -euo pipefail

AQUI="$(dirname "$(readlink -f "$0")")"
P3="$(readlink -f "$AQUI/../..")"
A8_ENV=${A8_ENV:-$P3/builds/a8/a8.env}
PREPARAR_ENGINE="$P3/builds/comum/i1/preparar-engine.sh"
MIN_LIVRE_GB=${MIN_LIVRE_GB:-4}

PACOTE=app-plates/1.0.0
IMAGENS=""
COM_CPU=1
while (( $# )); do
  case "$1" in
    --pacote)  PACOTE=${2:?--pacote precisa de um valor (ex.: app-epi/1.0.0)}; shift ;;
    --imagens) IMAGENS=$(readlink -f "${2:?--imagens precisa de uma pasta}"); shift ;;
    --sem-cpu) COM_CPU=0 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opção desconhecida: $1 (use --pacote, --imagens, --sem-cpu)" >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$A8_ENV" ]] || { echo "não achei $A8_ENV" >&2; exit 1; }
I1_REF=$(sed -n 's/^I1_REF=//p' "$A8_ENV")
SRC_DIR=$(sed -n 's/^SRC_DIR=//p' "$A8_ENV")
I1_ENGINES_DIR=$(sed -n 's/^I1_ENGINES_DIR=//p' "$A8_ENV")
[[ "$I1_REF" =~ ^[0-9a-f]{40}$ ]] || { echo "I1_REF inválido em $A8_ENV: '$I1_REF'" >&2; exit 1; }
: "${SRC_DIR:?SRC_DIR vazio em $A8_ENV}" "${I1_ENGINES_DIR:?I1_ENGINES_DIR vazio em $A8_ENV}"
IMG="ods-i1-gpu:$I1_REF"
PACOTE_C="/app/I1/artifacts/$PACOTE"

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else V=; A=; R=; N=; fi
etapa() { echo; echo "== $*"; }
erro()  { echo "${R}✘ $*${N}" >&2; exit 1; }

DATA=$(date +%Y-%m-%d-%H%M%S)
SAIDA="$AQUI/resultados/i1-gpu-$DATA"
mkdir -p "$SAIDA"
REL="$SAIDA.txt"
declare -a ITENS=()
FALHAS=0
item() {   # item <código> <PASSOU|FALHOU|AVISO> <texto>
  local cor=$V
  case "$2" in FALHOU) cor=$R; FALHAS=$((FALHAS + 1)) ;; AVISO) cor=$A ;; esac
  ITENS+=("$1 $2 — $3")
  echo "${cor}$1 $2${N} — $3"
}
livre_gb() { df -BG --output=avail / | tail -1 | tr -dc '0-9'; }
checar_disco() {
  local l; l=$(livre_gb)
  (( l >= MIN_LIVRE_GB )) || erro "só ${l} GB livres (mínimo ${MIN_LIVRE_GB} GB); pare e libere espaço"
  echo "  disco: ${l} GB livres"
}

# Container do I1 na GPU, com a pasta de engines e a pasta de saída do teste.
gpu() {   # gpu <modo das engines: ro|rw> <args do docker run…>
  local modo=$1; shift
  docker run --rm --runtime nvidia \
    -e P2_ENGINE_DIR=/opt/ods/engines -e P2_BACKEND="${P2_BACKEND_TESTE:-trt}" \
    -v "$I1_ENGINES_DIR:/opt/ods/engines:$modo" -v "$SAIDA:/saida" "$@"
}

DF_ANTES=$(df -h / | tail -1)
# Relatório: gravado no fim, ou quando o teste para antes (erro), com os itens até ali.
escrever_relatorio() {
  local cod=$?
  (( ${#ITENS[@]} )) || return "$cod"
  {
    echo "Teste individual do I1 na GPU (TensorRT via P2) — $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Placa: $(uname -n) · ${PLACA:-}"
    echo "Imagem: $IMG · pacote $PACOTE · imagens ${FONTE_C:-} (${N_IMG:-})"
    echo "Engines: $I1_ENGINES_DIR"
    echo
    printf '%s\n' "${ITENS[@]}"
    echo
    echo "Sonda GPU: ${SONDA_GPU:-}"
    (( COM_CPU )) && echo "Sonda CPU: ${SONDA_CPU:-}"
    echo "Disco antes:  $DF_ANTES"
    echo
    echo "Resumo: $(printf '%s\n' "${ITENS[@]}" | grep -c ' PASSOU ') passou, $FALHAS falhou, $(printf '%s\n' "${ITENS[@]}" | grep -c ' AVISO ') aviso"
    echo "Arquivos: $SAIDA/ (mensagens.jsonl, i1.log, engine.log, tegrastats.log)"
    echo "Disco depois: $(df -h / | tail -1)"
  } > "$REL"
  echo
  cat "$REL"
  return "$cod"
}
trap escrever_relatorio EXIT


etapa "G01 Placa"
PLACA=$(head -1 /etc/nv_tegra_release 2>/dev/null || echo "sem /etc/nv_tegra_release")
echo "  $(uname -m) · $PLACA"
checar_disco
if [[ "$(uname -m)" != aarch64 || ! -f /etc/nv_tegra_release ]]; then
  item G01 FALHOU "não é uma Jetson ($(uname -m)); este teste só faz sentido na placa"
  erro "rode na Jetson"
fi
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
  item G01 PASSOU "Jetson ($PLACA) com runtime nvidia no Docker"
else
  item G01 FALHOU "o Docker não tem o runtime nvidia (docker info | grep -i runtime)"
  erro "sem runtime nvidia não há GPU no container"
fi

etapa "Código e imagem ($IMG)"
if [[ ! -d "$SRC_DIR/i1/.git" ]]; then
  git clone --quiet https://github.com/ods-26-2/i1 "$SRC_DIR/i1"
fi
git -C "$SRC_DIR/i1" cat-file -e "$I1_REF^{commit}" 2>/dev/null || git -C "$SRC_DIR/i1" fetch --quiet origin
[[ -z "$(git -C "$SRC_DIR/i1" status --porcelain --untracked-files=no)" ]] \
  || erro "$SRC_DIR/i1 tem alterações locais; não mexo (git -C $SRC_DIR/i1 status)"
[[ "$(git -C "$SRC_DIR/i1" rev-parse HEAD)" == "$I1_REF" ]] || git -C "$SRC_DIR/i1" checkout --quiet --detach "$I1_REF"
echo "  i1 -> $(git -C "$SRC_DIR/i1" log -1 --format='%h %cs %s')"
if docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "  imagem já existe"
else
  echo "  construindo (a base nvcr.io/nvidia/l4t-jetpack:r36.4.0 tem vários GB; log em $SAIDA/build.log)"
  docker build -f "$SRC_DIR/i1/Dockerfile.jetson" -t "$IMG" "$SRC_DIR/i1" > "$SAIDA/build.log" 2>&1 \
    || { tail -20 "$SAIDA/build.log"; erro "o build da imagem falhou (log em $SAIDA/build.log)"; }
  docker builder prune -af >/dev/null
  checar_disco
fi

etapa "G02 TensorRT e P2 dentro da imagem"
if VERSOES=$(gpu ro "$IMG" python3 -c '
import os, importlib.metadata as md
import tensorrt
from p2.api import select_backend
backend = type(select_backend(os.environ)).__name__
print("TensorRT", tensorrt.__version__, "· p2", md.version("p2"), "· cuda-python", md.version("cuda-python"), "· backend", backend)
' 2>"$SAIDA/g02.err"); then
  item G02 PASSOU "$VERSOES"
else
  item G02 FALHOU "TensorRT/P2 não importam na imagem: $(tail -1 "$SAIDA/g02.err")"
  erro "sem TensorRT na imagem não há como seguir"
fi

etapa "G03 Engine de $PACOTE em $I1_ENGINES_DIR"
if [[ ! -d "$I1_ENGINES_DIR" ]]; then
  mkdir -p "$I1_ENGINES_DIR" 2>/dev/null \
    || erro "não consegui criar $I1_ENGINES_DIR. Uma vez só: sudo mkdir -p $I1_ENGINES_DIR && sudo chown $(id -un) $I1_ENGINES_DIR"
fi
t0=$SECONDS
if gpu rw -v "$PREPARAR_ENGINE:/p3/preparar-engine.sh:ro" "$IMG" \
     sh /p3/preparar-engine.sh "$PACOTE_C" FP16 2>&1 | tee "$SAIDA/engine.log"; then
  item G03 PASSOU "engine pronta em $((SECONDS - t0)) s ($(grep -m1 -oE 'já está|compilando' "$SAIDA/engine.log" || echo '?'))"
else
  item G03 FALHOU "p2-build falhou (log em $SAIDA/engine.log)"
  erro "sem engine não há inferência"
fi
checar_disco

etapa "G04 Inferência direta pelo P2 com tegrastats"
TEGRA=""
if command -v tegrastats >/dev/null; then
  tegrastats --interval 100 > "$SAIDA/tegrastats.log" 2>&1 &
  TEGRA=$!
  sleep 1
fi
SONDA='
import json, os, sys, numpy as np, p2
meta = json.load(open(sys.argv[1] + "/metadata.json"))
ref = meta["artifact_id"] + "-" + meta["artifact_version"]
h = p2.load(ref)
info = p2.info(h)
(nome, forma), = info["input_shape"].items()
x = np.random.rand(*forma).astype(np.float32)
for _ in range(10):
    p2.infer(h, {nome: x})
lat = []
for _ in range(int(sys.argv[2])):
    _, st = p2.infer(h, {nome: x})
    lat.append(st["latency_ms"])
maps = open("/proc/self/maps").read()
lat.sort()
print(json.dumps({
    "engine_version": info["engine_version"], "precision": info["precision"],
    "backend": os.environ.get("P2_BACKEND"),
    "libnvinfer": "libnvinfer" in maps, "onnxruntime": "onnxruntime" in maps,
    "lat_media_ms": round(sum(lat) / len(lat), 2), "lat_p95_ms": round(lat[int(len(lat) * 0.95) - 1], 2),
    "gpu_memory_mb": round(st["gpu_memory_mb"], 1), "n": len(lat)}))
'
SONDA_GPU=$(gpu ro "$IMG" python3 -c "$SONDA" "$PACOTE_C" 300 2>"$SAIDA/g04.err" | tail -1) || true
if [[ -n "$TEGRA" ]]; then sleep 1; kill "$TEGRA" 2>/dev/null || true; wait "$TEGRA" 2>/dev/null || true; fi
echo "  $SONDA_GPU"
GR3D_MAX=$(grep -oE 'GR3D_FREQ [0-9]+%' "$SAIDA/tegrastats.log" 2>/dev/null | awk '{print $2+0}' | sort -n | tail -1 || true)
read -r LIBNV LAT_GPU < <(python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1]); print(d["libnvinfer"], d["lat_media_ms"])
except Exception:
    print("erro -")' "$SONDA_GPU")
if [[ "$LIBNV" != True ]]; then
  item G04 FALHOU "a inferência pelo P2 não carregou libnvinfer ($(tail -1 "$SAIDA/g04.err" 2>/dev/null))"
elif [[ -z "$TEGRA" ]]; then
  item G04 AVISO "libnvinfer carregada, ${LAT_GPU} ms/quadro; sem tegrastats no host para ver GR3D_FREQ"
elif [[ "${GR3D_MAX:-0}" -gt 0 ]]; then
  item G04 PASSOU "libnvinfer carregada, ${LAT_GPU} ms/quadro, GR3D_FREQ até ${GR3D_MAX}%"
else
  item G04 FALHOU "libnvinfer carregada, mas GR3D_FREQ ficou em 0% (a GPU não trabalhou?)"
fi

etapa "G05 I1 (run_detector.py) nas imagens de teste"
if [[ -n "$IMAGENS" ]]; then
  FONTE=(-v "$IMAGENS:/imagens:ro"); FONTE_C=/imagens; N_IMG=$(find "$IMAGENS" -maxdepth 1 -type f -iregex '.*\.\(jpg\|jpeg\|png\|bmp\|webp\)' | wc -l)
else
  FONTE=(); FONTE_C="$PACOTE_C/fixtures"
  docker run --rm "$IMG" test -d "$FONTE_C" || FONTE_C=/app/I1/artifacts/app-plates/1.0.0/fixtures
  N_IMG=$(docker run --rm "$IMG" sh -c "ls $FONTE_C | grep -ciE '\.(jpg|jpeg|png|bmp|webp)$'")
fi
echo "  $N_IMG imagens em $FONTE_C"
set +e
gpu ro "${FONTE[@]}" "$IMG" python3 I1/run_detector.py --backend p2 \
  --metadata "$PACOTE_C/metadata.json" --source "$FONTE_C" --source-id teste-i1-gpu \
  --max-frames 100000 --conf 0.50 --mode stdout --output-jsonl /saida/mensagens.jsonl \
  > "$SAIDA/i1.log" 2>&1
COD=$?
set -e
sed -n '/Resumo/,$p' "$SAIDA/i1.log" | sed 's/^/  /'
if (( COD == 0 )); then item G05 PASSOU "run_detector.py terminou com código 0"
else item G05 FALHOU "run_detector.py terminou com código $COD (log em $SAIDA/i1.log)"; fi

etapa "G06–G08 Mensagens publicadas"
META_JSON=$(docker run --rm "$IMG" cat "$PACOTE_C/metadata.json")
while IFS='|' read -r cod res txt; do item "$cod" "$res" "$txt"; done < <(
python3 - "$SAIDA/mensagens.jsonl" "$N_IMG" "$META_JSON" "$SONDA_GPU" <<'PY'
import json, sys
caminho, n_img, meta, sonda = sys.argv[1], int(sys.argv[2]), json.loads(sys.argv[3]), sys.argv[4]
try:
    msgs = [json.loads(l) for l in open(caminho) if l.strip()]
except FileNotFoundError:
    msgs = []
try:
    engine = json.loads(sonda)["engine_version"]
except Exception:
    engine = meta["artifact_id"] + "-" + meta["artifact_version"] + "-fp16"
ok_schema = all(m.get("schema") == "ods.i1.detections" and m.get("producer") == "I1" for m in msgs)
if len(msgs) == n_img and msgs and ok_schema:
    print(f"G06|PASSOU|{len(msgs)} mensagens ods.i1.detections para {n_img} imagens (validadas pelo I1 contra o schema B1)")
else:
    print(f"G06|FALHOU|{len(msgs)} mensagens para {n_img} imagens (schema ok: {ok_schema})")
versoes = sorted({m.get("artifact_version") for m in msgs})
if msgs and versoes == [engine] and engine.endswith("-fp16"):
    print(f"G07|PASSOU|artifact_version = {engine} (engine TensorRT FP16)")
else:
    print(f"G07|FALHOU|artifact_version {versoes}, esperado [{engine}]")
classes = set(meta["classes"])
dets = [d for m in msgs for d in m["payload"]["detections"]]
com = sum(1 for m in msgs if m["payload"]["detections"])
fora = sorted({d["class"] for d in dets} - classes)
conf = [d["confidence"] for d in dets]
resumo = f"{len(dets)} detecções em {com}/{len(msgs)} imagens"
if conf:
    resumo += f", confiança {min(conf):.2f}–{max(conf):.2f}"
if fora:
    print(f"G08|FALHOU|{resumo}; classes fora do pacote: {fora}")
elif not dets:
    print(f"G08|FALHOU|nenhuma detecção nas imagens de teste")
elif com < len(msgs):
    print(f"G08|AVISO|{resumo} (alguma imagem sem detecção)")
else:
    print(f"G08|PASSOU|{resumo}")
PY
)

if (( COM_CPU )); then
  etapa "G09 Mesma inferência na CPU (ONNX Runtime do P2), para comparar"
  SONDA_CPU=$(P2_BACKEND_TESTE=ort gpu ro "$IMG" python3 -c "$SONDA" "$PACOTE_C" 20 2>>"$SAIDA/g04.err" | tail -1) || true
  echo "  $SONDA_CPU"
  LAT_CPU=$(python3 -c 'import json,sys
try: print(json.loads(sys.argv[1])["lat_media_ms"])
except Exception: print("-")' "$SONDA_CPU")
  if [[ "$LAT_CPU" != - && "$LAT_GPU" != - ]]; then
    item G09 AVISO "informativo: CPU ${LAT_CPU} ms/quadro × GPU ${LAT_GPU} ms/quadro ($(python3 -c "print(f'{$LAT_CPU/$LAT_GPU:.1f}')")× mais rápido na GPU)"
  else
    item G09 AVISO "informativo: não consegui medir a CPU (veja $SAIDA/g04.err)"
  fi
fi

(( FALHAS == 0 ))
