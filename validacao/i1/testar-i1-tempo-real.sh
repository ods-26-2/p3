#!/usr/bin/env bash
# testar-i1-tempo-real.sh — o I1 na GPU dá conta de um vídeo em tempo real? Quanto tempo leva?
#
# Parte 1 (sempre): o I1 lê o vídeo direto do arquivo, o mais rápido que consegue, sem Kafka
# (--mode stdout). Mede o tempo total, a vazão em quadros/s e o tempo de cada quadro, e compara
# com o fps do vídeo: se a vazão for maior, o I1 acompanha aquela câmera em tempo real.
#
# Parte 2 (se o A8 tiver rodado ./a8.sh testar há pouco): lê as mensagens que o I1 da cadeia
# gravou (/app/i1-eventos.jsonl do container i1) e mede o atraso real entre o P4 capturar o
# quadro e o I1 publicar a detecção, e quantos quadros do P4 o I1 deixou de processar.
#
#   ./testar-i1-tempo-real.sh                       vídeo VIDEO_DIR/cam0.mp4 do a8.env
#   ./testar-i1-tempo-real.sh --video /pasta/x.mp4  outro vídeo
#   ./testar-i1-tempo-real.sh --fps-alvo 30         compara com uma câmera de 30 quadros/s
#   ./testar-i1-tempo-real.sh --sem-cadeia          pula a parte 2
#
# Usa a imagem ods-i1-gpu:<I1_REF> e a engine que o ./a8.sh ou o ./testar-i1-gpu.sh já
# prepararam (este teste não constrói nada). Lê I1_REF, I1_ENGINES_DIR, I1_PACOTE e VIDEO_DIR de
# builds/a8/a8.env (troque com A8_ENV=<arquivo>).
# Resultado: validacao/i1/resultados/i1-tempo-real-<data>.txt (+ pasta com mensagens e logs).
#
# Itens:
#   R01 imagem, engine e runtime nvidia presentes   R04 vazão ≥ fps alvo (acompanha em tempo real)
#   R02 todos os quadros do vídeo processados       R05 tempo por quadro (p95) < intervalo entre quadros
#   R03 artifact_version …-fp16 (GPU)               R06 cadeia do A8: quadros do P4 perdidos e atraso
set -euo pipefail

AQUI="$(dirname "$(readlink -f "$0")")"
P3="$(readlink -f "$AQUI/../..")"
A8_ENV=${A8_ENV:-$P3/builds/a8/a8.env}

VIDEO=""
FPS_ALVO=""
COM_CADEIA=1
while (( $# )); do
  case "$1" in
    --video)      VIDEO=$(readlink -f "${2:?--video precisa de um arquivo}"); shift ;;
    --fps-alvo)   FPS_ALVO=${2:?--fps-alvo precisa de um número}; shift ;;
    --sem-cadeia) COM_CADEIA=0 ;;
    -h|--help)    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opção desconhecida: $1 (use --video, --fps-alvo, --sem-cadeia)" >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$A8_ENV" ]] || { echo "não achei $A8_ENV" >&2; exit 1; }
ler() { sed -n "s/^$1=//p" "$A8_ENV"; }
I1_REF=$(ler I1_REF); I1_ENGINES_DIR=$(ler I1_ENGINES_DIR); I1_PACOTE=$(ler I1_PACOTE); VIDEO_DIR=$(ler VIDEO_DIR)
[[ "$I1_REF" =~ ^[0-9a-f]{40}$ ]] || { echo "I1_REF inválido em $A8_ENV: '$I1_REF'" >&2; exit 1; }
VIDEO=${VIDEO:-$VIDEO_DIR/cam0.mp4}
IMG="ods-i1-gpu:$I1_REF"

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else V=; A=; R=; N=; fi
etapa() { echo; echo "== $*"; }

DATA=$(date +%Y-%m-%d-%H%M%S)
SAIDA="$AQUI/resultados/i1-tempo-real-$DATA"
mkdir -p "$SAIDA"
REL="$SAIDA.txt"
declare -a ITENS=() MEDIDAS=()
FALHAS=0
item() {   # item <código> <PASSOU|FALHOU|AVISO> <texto>
  local cor=$V
  case "$2" in FALHOU) cor=$R; FALHAS=$((FALHAS + 1)) ;; AVISO) cor=$A ;; esac
  ITENS+=("$1 $2 — $3")
  echo "${cor}$1 $2${N} — $3"
}
medida() { MEDIDAS+=("$*"); echo "  $*"; }

escrever_relatorio() {
  local cod=$?
  [[ -n "${TEG_PID:-}" ]] && kill "$TEG_PID" 2>/dev/null
  (( ${#ITENS[@]} )) || return "$cod"
  {
    echo "Teste de tempo real do I1 na GPU — $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Placa: $(uname -n) · $(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo '?')"
    echo "Imagem: $IMG · pacote $I1_PACOTE · vídeo $VIDEO"
    echo
    echo "Medidas:"
    printf '  %s\n' "${MEDIDAS[@]}"
    echo
    printf '%s\n' "${ITENS[@]}"
    echo
    echo "Resumo: $(printf '%s\n' "${ITENS[@]}" | grep -c ' PASSOU ') passou, $FALHAS falhou, $(printf '%s\n' "${ITENS[@]}" | grep -c ' AVISO ') aviso"
    echo "Arquivos: $SAIDA/ (mensagens.jsonl, i1.log, tegrastats.log, cadeia.jsonl)"
  } > "$REL"
  echo; cat "$REL"
  return "$cod"
}
trap escrever_relatorio EXIT

# Mesma ideia do ./a8.sh testar: na Jetson a GPU usa a RAM do sistema, e com o A8 de pé o
# TensorRT pode não conseguir memória para criar o contexto. Esvaziar o cache não apaga dados.
liberar_memoria() {
  local antes depois cmd='sync; echo 3 > /proc/sys/vm/drop_caches'
  antes=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
  if { [[ -t 0 ]] && sudo sh -c "$cmd"; } || sudo -n sh -c "$cmd" 2>/dev/null; then
    depois=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
    echo "  memória livre: ${antes} MB → ${depois} MB (cache de páginas esvaziado)"
  else
    echo "  memória livre: ${antes} MB (sem sudo para esvaziar o cache)"
  fi
}

# ---------------------------------------------------------------------------------------------
etapa "R01 Conferindo imagem, engine e GPU"
ok_r01=1
docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia || { ok_r01=0; motivo="Docker sem runtime nvidia"; }
docker image inspect "$IMG" >/dev/null 2>&1 || { ok_r01=0; motivo="imagem $IMG não existe (rode ./testar-i1-gpu.sh ou ./a8.sh antes)"; }
# O P2 cria a pasta da engine com mkdtemp (0700, dona root): o usuário ods não lista o conteúdo.
# A conferência roda dentro de um container, como root, igual ao I1.
[[ "$ok_r01" == 0 ]] || docker run --rm --entrypoint "" -v "$I1_ENGINES_DIR:/e:ro" "$IMG" sh -c 'ls /e/*/manifest.json' >/dev/null 2>&1 \
  || { ok_r01=0; motivo="nenhuma engine em $I1_ENGINES_DIR (rode ./testar-i1-gpu.sh antes)"; }
[[ -f "$VIDEO" ]] || { ok_r01=0; motivo="vídeo $VIDEO não existe"; }
if (( ! ok_r01 )); then item R01 FALHOU "$motivo"; exit 1; fi
item R01 PASSOU "imagem $IMG, engine em $I1_ENGINES_DIR, runtime nvidia"

DIR_VIDEO=$(dirname "$VIDEO"); ARQ_VIDEO=$(basename "$VIDEO")
# fps, quadros, largura e altura do vídeo, lidos com o OpenCV da própria imagem
read -r FPS_VIDEO QUADROS LARG ALT < <(docker run --rm --entrypoint "" -v "$DIR_VIDEO:/videos:ro" "$IMG" \
  python3 -c "import cv2; c=cv2.VideoCapture('/videos/$ARQ_VIDEO'); print(round(c.get(5),3), int(c.get(7)), int(c.get(3)), int(c.get(4)))" | tail -1) || true
if [[ -z "${FPS_VIDEO:-}" ]] || ! awk -v f="$FPS_VIDEO" 'BEGIN { exit !(f > 0) }'; then
  item R01 FALHOU "não consegui ler fps e quadros de $VIDEO com o OpenCV da imagem"; exit 1
fi
FPS_ALVO=${FPS_ALVO:-$FPS_VIDEO}
DURACAO=$(awk -v q="$QUADROS" -v f="$FPS_VIDEO" 'BEGIN { printf "%.1f", (f > 0 ? q / f : 0) }')
medida "Vídeo: ${LARG}x${ALT}, $QUADROS quadros a $FPS_VIDEO quadros/s = ${DURACAO} s de vídeo"
medida "Alvo de tempo real: $FPS_ALVO quadros/s (um quadro a cada $(awk -v f="$FPS_ALVO" 'BEGIN{printf "%.1f", 1000/f}') ms)"

# ---------------------------------------------------------------------------------------------
etapa "Parte 1: I1 lendo o vídeo o mais rápido que consegue (GPU, sem Kafka)"
liberar_memoria
TEG_PID=""
if command -v tegrastats >/dev/null; then
  tegrastats --interval 500 > "$SAIDA/tegrastats.log" 2>/dev/null & TEG_PID=$!
fi
T0=$(date +%s.%N)
set +e
docker run --rm --runtime nvidia \
  -e P2_ENGINE_DIR=/opt/ods/engines -e P2_BACKEND=trt \
  -v "$I1_ENGINES_DIR:/opt/ods/engines:ro" -v "$DIR_VIDEO:/videos:ro" -v "$SAIDA:/saida" \
  "$IMG" python3 I1/run_detector.py --backend p2 \
    --metadata "/app/I1/artifacts/$I1_PACOTE/metadata.json" \
    --source "/videos/$ARQ_VIDEO" --source-id teste-tempo-real \
    --max-frames 100000000 --conf 0.50 --mode stdout \
    --output-jsonl /saida/mensagens.jsonl > "$SAIDA/i1.log" 2>&1
COD_I1=$?
set -e
T1=$(date +%s.%N)
[[ -n "$TEG_PID" ]] && { kill "$TEG_PID" 2>/dev/null; wait "$TEG_PID" 2>/dev/null || true; TEG_PID=""; }
TOTAL=$(awk -v a="$T0" -v b="$T1" 'BEGIN { printf "%.1f", b - a }')
echo "  I1 terminou com código $COD_I1 em ${TOTAL} s (inclui subir o container e carregar a engine)"
if [[ "$COD_I1" != 0 ]]; then
  echo "  últimas linhas do log:"; tail -5 "$SAIDA/i1.log" | sed 's/^/    /'
fi

# Análise das mensagens: tempo entre o I1 ler o quadro (captured_at) e publicar (published_at),
# e o intervalo entre a primeira e a última publicação (vazão).
INF_MEDIA=$(sed -n 's/.*Latência média de inferência: *\([0-9.]*\) ms.*/\1/p' "$SAIDA/i1.log" | tail -1)
GR3D_MAX=$(grep -o 'GR3D_FREQ [0-9]*%' "$SAIDA/tegrastats.log" 2>/dev/null | awk '{v=$2+0; if (v>m) m=v} END {print m+0}')
ANALISE=$(python3 - "$SAIDA/mensagens.jsonl" <<'PY' 2>"$SAIDA/analise.err" || true
import json, sys
from datetime import datetime
def t(s): return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
msgs = []
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        msgs = [json.loads(l) for l in f if l.strip()]
except FileNotFoundError:
    pass
if not msgs:
    print("NMSG=0"); sys.exit()
lat = sorted((t(m["published_at"]) - t(m["captured_at"])) * 1000 for m in msgs)
p = lambda q: lat[min(len(lat) - 1, int(q * len(lat)))]
span = t(msgs[-1]["published_at"]) - t(msgs[0]["captured_at"])
vers = sorted({m.get("artifact_version", "?") for m in msgs})
dets = sum(len(m.get("payload", {}).get("detections", [])) for m in msgs)
print(f"NMSG={len(msgs)} SPAN={span:.2f} VAZAO={len(msgs) / span if span > 0 else 0:.1f} "
      f"P50={p(0.5):.1f} P95={p(0.95):.1f} MAX={lat[-1]:.1f} DETS={dets} VERS={','.join(vers)}")
PY
)
[[ -n "$ANALISE" ]] || ANALISE="NMSG=0"
NMSG=0 SPAN=0 VAZAO=0 P50=0 P95=0 MAX=0 DETS=0 VERS=""
for kv in $ANALISE; do declare "$kv"; done

if (( NMSG == 0 )); then
  item R02 FALHOU "nenhuma mensagem gravada (código $COD_I1; veja $SAIDA/i1.log e analise.err)"
  exit 1
fi
CARGA=$(awk -v t="$TOTAL" -v s="$SPAN" 'BEGIN { printf "%.1f", t - s }')
medida "Tempo total: ${TOTAL} s = ${CARGA} s para subir e carregar a engine + ${SPAN} s processando"
medida "Vazão: ${VAZAO} quadros/s ($NMSG quadros em ${SPAN} s; o vídeo tem ${DURACAO} s)"
medida "Tempo por quadro (ler → publicar): mediana ${P50} ms · p95 ${P95} ms · máximo ${MAX} ms"
medida "Inferência média (só a GPU, medida pelo I1): ${INF_MEDIA:-?} ms"
medida "GPU: GR3D_FREQ até ${GR3D_MAX:-?}% · detecções: $DETS"

# O total de quadros que o OpenCV informa pode errar por 1 ou 2 em MP4: tolera 1%.
if [[ "$COD_I1" == 0 ]] && awk -v n="$NMSG" -v q="$QUADROS" 'BEGIN { exit !(n >= q * 0.99) }'; then
  item R02 PASSOU "$NMSG de $QUADROS quadros processados, código 0"
else
  item R02 FALHOU "$NMSG de $QUADROS quadros processados, código $COD_I1"
fi
case "$VERS" in
  *-fp16) item R03 PASSOU "artifact_version $VERS (TensorRT FP16 na GPU)" ;;
  *)      item R03 FALHOU "artifact_version '$VERS' (esperado …-fp16)" ;;
esac
FOLGA=$(awk -v v="$VAZAO" -v a="$FPS_ALVO" 'BEGIN { printf "%.1f", (a > 0 ? v / a : 0) }')
if awk -v v="$VAZAO" -v a="$FPS_ALVO" 'BEGIN { exit !(v >= a) }'; then
  item R04 PASSOU "${VAZAO} quadros/s ≥ ${FPS_ALVO} do alvo: acompanha em tempo real com folga de ${FOLGA}×"
else
  item R04 FALHOU "${VAZAO} quadros/s < ${FPS_ALVO} do alvo (${FOLGA}×): não acompanha em tempo real"
fi
INTERVALO=$(awk -v f="$FPS_ALVO" 'BEGIN { printf "%.1f", 1000 / f }')
if awk -v p="$P95" -v i="$INTERVALO" 'BEGIN { exit !(p < i) }'; then
  item R05 PASSOU "p95 de ${P95} ms por quadro < ${INTERVALO} ms entre quadros"
else
  item R05 AVISO "p95 de ${P95} ms por quadro ≥ ${INTERVALO} ms entre quadros (quadros podem enfileirar)"
fi

# ---------------------------------------------------------------------------------------------
if (( COM_CADEIA )); then
  etapa "Parte 2: I1 da cadeia do A8 (ritmo real do P4)"
  C=$(docker ps -aq --filter label=com.docker.compose.project=ods-a8 --filter label=com.docker.compose.service=i1 | head -1)
  if [[ -z "$C" ]] || ! docker cp "$C":/app/i1-eventos.jsonl - 2>/dev/null | tar -xO > "$SAIDA/cadeia.jsonl" || [[ ! -s "$SAIDA/cadeia.jsonl" ]]; then
    item R06 AVISO "sem mensagens do I1 da cadeia (rode ./a8.sh testar antes; o container i1 é recriado a cada teste)"
  else
    CADEIA=$(python3 - "$SAIDA/cadeia.jsonl" <<'PY' 2>>"$SAIDA/analise.err" || true
import json, sys
from datetime import datetime
def t(s): return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
msgs = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
sessao = msgs[-1]["session_id"]
msgs = [m for m in msgs if m["session_id"] == sessao]
idx = sorted(m["payload"]["frame_index"] for m in msgs)
lat = sorted((t(m["published_at"]) - t(m["captured_at"])) * 1000 for m in msgs)
p = lambda q: lat[min(len(lat) - 1, int(q * len(lat)))]
buracos = sum(b - a - 1 for a, b in zip(idx, idx[1:]) if b - a > 1)
print(f"CN={len(msgs)} CPRIM={idx[0]} CULT={idx[-1]} CPERD={buracos} "
      f"CP50={p(0.5):.1f} CP95={p(0.95):.1f} CMAX={lat[-1]:.1f} CSESSAO={sessao[:8]}")
PY
)
    CN=0 CPRIM=0 CULT=0 CPERD=0 CP50=0 CP95=0 CMAX=0 CSESSAO=""
    for kv in ${CADEIA:-}; do declare "$kv"; done
    if (( CN == 0 )); then
      item R06 AVISO "não consegui ler as mensagens da cadeia (veja $SAIDA/analise.err)"
    else
      medida "Cadeia (sessão $CSESSAO): $CN quadros publicados, frame_index $CPRIM a $CULT"
      medida "Cadeia: atraso P4 capturou → I1 publicou: mediana ${CP50} ms · p95 ${CP95} ms · máximo ${CMAX} ms"
      medida "Cadeia: quadros perdidos no meio $CPERD · no começo (antes do I1 conectar) $CPRIM"
      if (( CPERD == 0 && CPRIM <= 5 )); then
        item R06 PASSOU "cadeia sem quadros perdidos; atraso p95 ${CP95} ms"
      else
        item R06 AVISO "cadeia perdeu $CPERD quadro(s) no meio e $CPRIM no começo; atraso p95 ${CP95} ms"
      fi
    fi
  fi
fi

(( FALHAS == 0 ))
