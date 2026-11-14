#!/usr/bin/env bash
# testar-i1-servico.sh — os testes do próprio I1, rodando no mesmo serviço que a build do A8 sobe.
#
# Lê a definição do serviço "i1" do builds/a8/docker-compose.yml (docker compose config) e
# roda um container com exatamente a mesma imagem, runtime (nvidia), variáveis de ambiente
# (P2_BACKEND=trt, P2_ENGINE_DIR, ODS_KAFKA_BROKER…) e volumes (engines). Só fica de fora o
# "ipc: service:p4" e a memória compartilhada /tmp, que ligam o I1 ao P4 tocando vídeo: sem
# eles os testes rodam com o P4 parado. Nada é publicado no Kafka.
#
# Itens:
#   S01 a imagem do serviço existe e é a do commit fixado (I1_REF, branch develop)
#   S02 a suíte de testes do repositório do I1 (I1/tests, unittest) dentro do serviço
#       (o test_05 precisa do ultralytics, que a imagem Jetson não instala: erro esperado)
#   S03 o comando padrão da imagem (CMD do Dockerfile.jetson: run_detector nas fixtures,
#       backend p2) dentro do serviço: código 0, mensagens válidas e artifact_version …-fp16
#
#   ./testar-i1-servico.sh
# Resultado: validacao/i1/resultados/i1-servico-<data>.txt (+ pasta com as saídas completas).
set -euo pipefail
[[ -n "${LC_ALL:-}" ]] && export LC_ALL=C.UTF-8
export LC_NUMERIC=C

AQUI="$(dirname "$(readlink -f "$0")")"
P3="$(readlink -f "$AQUI/../..")"
BUILD="$P3/builds/a8"
case "${1:-}" in -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; NC=$'\e[0m'; else V=; A=; R=; NC=; fi
etapa() { echo; echo "== $*"; }
erro()  { echo "${R}✘ $*${NC}" >&2; exit 1; }

DATA=$(date +%Y-%m-%d-%H%M%S)
SAIDA="$AQUI/resultados/i1-servico-$DATA"
mkdir -p "$SAIDA"
REL="$SAIDA.txt"
declare -a ITENS=()
FALHAS=0
item() {
  local cor=$V
  case "$2" in FALHOU) cor=$R; FALHAS=$((FALHAS + 1)) ;; AVISO) cor=$A ;; esac
  ITENS+=("$1 $2 — $3"); echo "${cor}$1 $2${NC} — $3"
}
relatorio() {
  local cod=$?
  (( ${#ITENS[@]} )) || return "$cod"
  {
    echo "Testes do I1 no serviço da build do A8 — $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Placa: $(uname -n) · $(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo '?')"
    echo "Serviço: builds/a8 → i1 · imagem ${IMG:-?}"
    echo "Configuração usada (do docker compose config):"
    sed 's/^/  /' "$SAIDA/servico.txt" 2>/dev/null || true
    echo
    printf '%s\n' "${ITENS[@]}"
    echo
    echo "Resumo: $(printf '%s\n' "${ITENS[@]}" | grep -c ' PASSOU ') passou, $FALHAS falhou, $(printf '%s\n' "${ITENS[@]}" | grep -c ' AVISO ') aviso"
    echo "Arquivos: $SAIDA/ (unittest.txt, cmd-padrao.txt, servico.txt)"
  } > "$REL"
  echo; cat "$REL"
  return "$cod"
}
trap relatorio EXIT

# ---- definição do serviço -------------------------------------------------------------------
etapa "Lendo o serviço i1 de builds/a8/docker-compose.yml"
cd "$BUILD"
SEC=a8.secrets.env
if [[ ! -f "$SEC" ]]; then
  # Sem os segredos reais, valores de mentira bastam para renderizar o compose (o i1 não usa)
  SEC="$SAIDA/segredos-falsos.env"
  grep -oE '^[A-Z0-9_]+=' a8.secrets.env.exemplo | sed 's/=$/=nao-usado/' > "$SEC"
fi
docker compose --env-file a8.env --env-file "$SEC" --profile video config --format json > "$SAIDA/compose.json" \
  || erro "docker compose config falhou em $BUILD"
# Gera os argumentos do docker run (um por linha) e um resumo legível
python3 - "$SAIDA/compose.json" "$SAIDA/args.txt" "$SAIDA/servico.txt" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))["services"]["i1"]
args, resumo = [], []
img = s["image"]; resumo.append(f"imagem: {img}")
if s.get("runtime"):
    args += ["--runtime", s["runtime"]]; resumo.append(f"runtime: {s['runtime']}")
for k, v in sorted((s.get("environment") or {}).items()):
    args += ["-e", f"{k}={v}"]; resumo.append(f"env: {k}={v}")
for vol in s.get("volumes") or []:
    if vol.get("type") == "bind":
        ro = ":ro" if vol.get("read_only") else ""
        args += ["-v", f"{vol['source']}:{vol['target']}{ro}"]; resumo.append(f"volume: {vol['source']} → {vol['target']}{ro}")
    else:
        resumo.append(f"fora do teste: volume {vol.get('source')} → {vol.get('target')} (memória compartilhada com o P4)")
if s.get("ipc"):
    resumo.append(f"fora do teste: ipc {s['ipc']} (precisa do P4 tocando)")
open(sys.argv[2], "w").write("\n".join(args) + "\n")
open(sys.argv[3], "w").write("\n".join(resumo) + "\n")
PY
IMG=$(sed -n 's/^imagem: //p' "$SAIDA/servico.txt")
mapfile -t ARGS < "$SAIDA/args.txt"
sed 's/^/  /' "$SAIDA/servico.txt"
servico() { docker run --rm "${ARGS[@]}" "$@"; }

# ---- S01 ------------------------------------------------------------------------------------
I1_REF=$(sed -n 's/^I1_REF=//p' a8.env)
if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  item S01 FALHOU "a imagem $IMG não existe (rode ./a8.sh)"; exit 1
fi
if [[ "$IMG" == *":$I1_REF" ]]; then
  item S01 PASSOU "imagem $IMG ($(docker image inspect -f '{{.Size}}' "$IMG" | awk '{printf "%.1f GB", $1/1e9}')), commit fixado da develop"
else
  item S01 FALHOU "o serviço usa $IMG, mas o I1_REF do a8.env é $I1_REF"
fi

# ---- S02: suíte do repositório --------------------------------------------------------------
etapa "S02 Suíte de testes do I1 (I1/tests) dentro do serviço"
set +e
servico "$IMG" python3 -m unittest discover -s I1/tests -p "test_*.py" -v > "$SAIDA/unittest.txt" 2>&1
COD=$?
set -e
read -r RAN OKS ERROS FALHAS_T PULADOS < <(python3 - "$SAIDA/unittest.txt" <<'PY'
import re, sys
t = open(sys.argv[1], errors="ignore").read()
# O resumo final do unittest é confiável; as linhas "... ok" se misturam com os logs dos testes.
ran = re.search(r"^Ran (\d+) tests?", t, re.M)
fim = re.search(r"^(OK|FAILED)(?: \((.*)\))?\s*$", t, re.M)
conta = dict(re.findall(r"(\w+)=(\d+)", fim.group(2) or "")) if fim else {}
n, e, f, p = (int(ran.group(1)) if ran else 0), int(conta.get("errors", 0)), int(conta.get("failures", 0)), int(conta.get("skipped", 0))
print(n, n - e - f - p, e, f, p)
PY
)
# Testes com problema, e se o único é o test_05 por falta do ultralytics
PROBLEMAS=$(grep -E '^(ERROR|FAIL): ' "$SAIDA/unittest.txt" | sed -E 's/^(ERROR|FAIL): ([^ ]+).*/\2/' | tr '\n' ' ' || true)
SO_ULTRA=0
if [[ "$PROBLEMAS" == "test_05_t16_integracao_degrau_a_onnx_real " ]] && grep -q "No module named 'ultralytics'" "$SAIDA/unittest.txt"; then SO_ULTRA=1; fi
echo "  $RAN testes: $OKS ok, $ERROS erro(s), $FALHAS_T falha(s), $PULADOS pulado(s) (código $COD)"
if (( RAN == 0 )); then
  item S02 FALHOU "a suíte não rodou (veja $SAIDA/unittest.txt)"
elif (( ERROS + FALHAS_T == 0 )); then
  item S02 PASSOU "$RAN testes: $OKS ok, $PULADOS pulado(s), nenhum erro ou falha"
elif (( SO_ULTRA )); then
  item S02 PASSOU "$OKS de $RAN testes ok; só o test_05 deu erro, esperado: precisa do ultralytics (caminho de CPU), que a imagem Jetson não instala"
else
  item S02 FALHOU "$OKS de $RAN testes ok; com problema: $PROBLEMAS(veja $SAIDA/unittest.txt)"
fi

# ---- S03: comando padrão da imagem ----------------------------------------------------------
etapa "S03 Comando padrão da imagem (CMD do Dockerfile.jetson) dentro do serviço"
mapfile -t CMD_PADRAO < <(docker image inspect -f '{{range .Config.Cmd}}{{println .}}{{end}}' "$IMG" | sed '/^$/d')
echo "  ${CMD_PADRAO[*]}"
set +e
servico "$IMG" "${CMD_PADRAO[@]}" > "$SAIDA/cmd-padrao.txt" 2>&1
COD=$?
set -e
read -r NMSG VERS DETS < <(python3 - "$SAIDA/cmd-padrao.txt" <<'PY'
import json, sys
msgs = []
for l in open(sys.argv[1], errors="ignore"):
    l = l.strip()
    if l.startswith("{") and '"schema": "ods.i1.detections"' in l:
        try: msgs.append(json.loads(l))
        except ValueError: pass
vers = sorted({m.get("artifact_version", "?") for m in msgs}) or ["-"]
print(len(msgs), ",".join(vers), sum(len(m["payload"]["detections"]) for m in msgs))
PY
)
echo "  código $COD · $NMSG mensagens · artifact_version $VERS · $DETS detecções"
if [[ "$COD" == 0 && "$NMSG" -gt 0 && "$VERS" == *-fp16 && "$VERS" != *,* ]]; then
  item S03 PASSOU "código 0, $NMSG mensagens validadas pelo I1 (schema B1), $DETS detecções, artifact_version $VERS (TensorRT FP16 na GPU)"
else
  item S03 FALHOU "código $COD, $NMSG mensagens, artifact_version '$VERS' (esperado …-fp16; veja $SAIDA/cmd-padrao.txt)"
fi

(( FALHAS == 0 ))
