#!/usr/bin/env bash
# testar-jetson-clocks.sh — a placa aguenta ficar com o jetson_clocks ligado o tempo todo?
#
# Mede, na própria Jetson, o que muda com os relógios fixos no máximo, em três fases:
#   1. base       relógios dinâmicos (como a placa está hoje), sem carga extra
#   2. parada     jetson_clocks ligado, sem carga extra (custo de deixar ligado "à toa")
#   3. carga      jetson_clocks ligado e a GPU em carga contínua (inferência do I1 sem pausa,
#                 o pior caso: bem mais pesado que o A8 com uma câmera de 10 quadros/s)
# Em cada fase grava o tegrastats (temperaturas, potência, uso da GPU) e a ventoinha.
# Ao final (ou se for interrompido com Ctrl+C) restaura os relógios como estavam.
#
#   ./testar-jetson-clocks.sh                  5 min por fase parada e 30 min de carga (~40 min)
#   ./testar-jetson-clocks.sh --carga 60       60 min de carga
#   ./testar-jetson-clocks.sh --repouso 2 --carga 10   rodada curta para conferir o script
#
# Precisa de sudo (jetson_clocks e leitura de eventos do kernel). Não para nem recria nenhum
# container: o Kafka da turma e as builds que estiverem de pé continuam rodando (e entram na
# medida, como numa operação real).
# Usa a imagem ods-i1-gpu:<I1_REF> e a engine que o ./a8.sh já preparou (builds/a8/a8.env).
# Resultado: validacao/placa/resultados/jetson-clocks-<data>.txt (+ pasta com os logs).
#
# Itens:
#   J01 temperatura máxima abaixo do primeiro limite de redução de desempenho (trip passivo),
#       com folga de 10 °C
#   J02 nenhum evento de sobrecorrente (OC) do regulador de energia
#   J03 desempenho estável sob carga (último trecho ≥ 90% do primeiro: sem redução por calor)
#   J04 o Kafka da turma continuou de pé
#   J05 informativo: quanto custa deixar ligado (potência, temperatura e ventoinha, parado)
set -euo pipefail
# Números com ponto, independente do locale (ver validacao/i1/testar-i1-tempo-real.sh)
[[ -n "${LC_ALL:-}" ]] && export LC_ALL=C.UTF-8
export LC_NUMERIC=C

AQUI="$(dirname "$(readlink -f "$0")")"
P3="$(readlink -f "$AQUI/../..")"
A8_ENV=${A8_ENV:-$P3/builds/a8/a8.env}

REPOUSO_MIN=5
# Só para simular o script fora da placa (ex.: SEG_POR_MIN=1 faz cada "minuto" durar 1 s)
SEG_POR_MIN=${SEG_POR_MIN:-60}
CARGA_MIN=30
while (( $# )); do
  case "$1" in
    --repouso) REPOUSO_MIN=${2:?--repouso precisa de minutos}; shift ;;
    --carga)   CARGA_MIN=${2:?--carga precisa de minutos}; shift ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opção desconhecida: $1 (use --repouso, --carga)" >&2; exit 2 ;;
  esac
  shift
done

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; NC=$'\e[0m'; else V=; A=; R=; NC=; fi
etapa() { echo; echo "== $(date +%H:%M:%S) $*"; }
erro()  { echo "${R}✘ $*${NC}" >&2; exit 1; }

command -v tegrastats >/dev/null || erro "sem tegrastats: rode na Jetson"
command -v jetson_clocks >/dev/null || erro "sem jetson_clocks: rode na Jetson"
[[ -f "$A8_ENV" ]] || erro "não achei $A8_ENV"
ler() { sed -n "s/^$1=//p" "$A8_ENV"; }
I1_REF=$(ler I1_REF); I1_ENGINES_DIR=$(ler I1_ENGINES_DIR); I1_PACOTE=$(ler I1_PACOTE)
IMG="ods-i1-gpu:$I1_REF"
docker image inspect "$IMG" >/dev/null 2>&1 || erro "imagem $IMG não existe (rode ./a8.sh antes)"

DATA=$(date +%Y-%m-%d-%H%M%S)
SAIDA="$AQUI/resultados/jetson-clocks-$DATA"
mkdir -p "$SAIDA"
REL="$SAIDA.txt"
ESTADO="$SAIDA/clocks-antes.conf"
declare -a ITENS=() MEDIDAS=()
FALHAS=0
item() {
  local cor=$V
  case "$2" in FALHOU) cor=$R; FALHAS=$((FALHAS + 1)) ;; AVISO) cor=$A ;; esac
  ITENS+=("$1 $2 — $3"); echo "${cor}$1 $2${NC} — $3"
}
medida() { MEDIDAS+=("$*"); echo "  $*"; }

echo "Este teste leva ~$((2 * REPOUSO_MIN + CARGA_MIN)) min e liga o jetson_clocks na placa (restaurado no fim)."
sudo -v || erro "precisa de sudo"
# Mantém o sudo válido durante o teste (o prazo padrão é 15 min)
# Saída em /dev/null: senão o laço segura o terminal ou um pipe aberto até 60 s depois do fim.
( while sleep 60; do sudo -n true || exit; done ) >/dev/null 2>&1 & SUDO_PID=$!

TEG_PID=""; SONDA_C=""; LIGADO=0
finalizar() {
  local cod=$?
  [[ -n "$TEG_PID" ]] && kill "$TEG_PID" 2>/dev/null
  [[ -n "$SONDA_C" ]] && docker rm -f "$SONDA_C" >/dev/null 2>&1
  if (( LIGADO )); then
    sudo jetson_clocks --restore "$ESTADO" >/dev/null 2>&1 \
      && echo "relógios restaurados ($ESTADO)" \
      || echo "${R}ATENÇÃO: não consegui restaurar. Rode: sudo jetson_clocks --restore $ESTADO${NC}"
  fi
  kill "$SUDO_PID" 2>/dev/null
  if (( ${#ITENS[@]} )); then
    {
      echo "Teste de resistência com jetson_clocks — $(date '+%Y-%m-%d %H:%M:%S %z')"
      echo "Placa: $(uname -n) · $(tr -d '\0' </proc/device-tree/model 2>/dev/null) · $(sudo -n nvpmodel -q 2>/dev/null | head -1)"
      echo "Fases: base ${REPOUSO_MIN} min · parada ${REPOUSO_MIN} min · carga ${CARGA_MIN} min (GPU sem pausa)"
      echo "Containers de pé durante o teste: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
      echo
      echo "Medidas:"; printf '  %s\n' "${MEDIDAS[@]}"
      echo
      printf '%s\n' "${ITENS[@]}"
      echo
      echo "Resumo: $(printf '%s\n' "${ITENS[@]}" | grep -c ' PASSOU ') passou, $FALHAS falhou, $(printf '%s\n' "${ITENS[@]}" | grep -c ' AVISO ') aviso"
      echo "Arquivos: $SAIDA/ (tegrastats-*.log, sonda.log, limites.txt)"
    } > "$REL"
    echo; cat "$REL"
  fi
  return "$cod"
}
trap finalizar EXIT
trap 'exit 130' INT TERM

# ---- limites e contadores do kernel ---------------------------------------------------------
# Limites térmicos: o menor "passive" é onde a placa começa a reduzir os relógios por calor.
for z in "${TERMICO:-/sys/class/thermal}"/thermal_zone*; do
  [[ -r "$z/type" ]] || continue
  for t in "$z"/trip_point_*_type; do
    [[ -r "$t" ]] || continue
    printf '%s %s %s\n' "$(cat "$z/type")" "$(cat "$t")" "$(( $(cat "${t%_type}_temp") / 1000 ))"
  done
done > "$SAIDA/limites.txt" 2>/dev/null || true
TRIP=$(awk '$2 == "passive" {print $3}' "$SAIDA/limites.txt" | sort -n | head -1)
# Eventos de sobrecorrente (OC) do monitor de energia, quando o kernel os expõe
contar_oc() { find /sys/class/hwmon/ /sys/bus/i2c/devices/ -name 'oc*_event_cnt' 2>/dev/null | sort -u | xargs -r cat 2>/dev/null | awk '{s += $1} END {print s + 0}'; }
TEM_OC=$(find /sys/class/hwmon/ /sys/bus/i2c/devices/ -name 'oc*_event_cnt' 2>/dev/null | head -1)
OC_ANTES=$(contar_oc)
ventoinha() { cat /sys/class/hwmon/hwmon*/pwm1 2>/dev/null | head -1 || echo "?"; }
KAFKA_ANTES=$(docker ps --filter name='^kafka$' --format '{{.Status}}' || true)

fase() {   # fase <nome> <segundos>: grava o tegrastats durante a fase
  tegrastats --interval 1000 > "$SAIDA/tegrastats-$1.log" 2>/dev/null & TEG_PID=$!
  sleep "$2"
  kill "$TEG_PID" 2>/dev/null; wait "$TEG_PID" 2>/dev/null || true; TEG_PID=""
  echo "  ventoinha (pwm 0–255) no fim da fase: $(ventoinha)" | tee "$SAIDA/ventoinha-$1.txt"
}
resumo_fase() {   # potência média/máx (mW), temperatura tj média/máx (°C), GR3D médio (%)
  python3 - "$SAIDA/tegrastats-$1.log" <<'PY'
import re, sys
pot, tj, gpu = [], [], []
for l in open(sys.argv[1], errors="ignore"):
    m = re.search(r"VDD_IN (\d+)mW", l);        pot += [int(m.group(1))] if m else []
    m = re.search(r"tj@([\d.]+)C", l);          tj += [float(m.group(1))] if m else []
    m = re.search(r"GR3D_FREQ (\d+)%", l);      gpu += [int(m.group(1))] if m else []
med = lambda v: sum(v) / len(v) if v else 0
print(f"POT_MED={med(pot)/1000:.1f} POT_MAX={max(pot or [0])/1000:.1f} "
      f"TJ_MED={med(tj):.1f} TJ_MAX={max(tj or [0]):.1f} GPU_MED={med(gpu):.0f} N={len(pot)}")
PY
}

# ---- fase 1: base ---------------------------------------------------------------------------
etapa "Fase 1/3: base (relógios dinâmicos), ${REPOUSO_MIN} min"
fase base $((REPOUSO_MIN * SEG_POR_MIN))
eval "$(resumo_fase base | sed 's/\([A-Z_]*\)=/B_\1=/g')"

# ---- fase 2: jetson_clocks parado -----------------------------------------------------------
etapa "Fase 2/3: jetson_clocks ligado, sem carga, ${REPOUSO_MIN} min"
sudo jetson_clocks --store "$ESTADO" >/dev/null
sudo jetson_clocks
LIGADO=1
sudo jetson_clocks --show > "$SAIDA/clocks-ligado.txt" 2>&1 || true
fase parada $((REPOUSO_MIN * SEG_POR_MIN))
eval "$(resumo_fase parada | sed 's/\([A-Z_]*\)=/P_\1=/g')"

# ---- fase 3: carga contínua na GPU ----------------------------------------------------------
etapa "Fase 3/3: jetson_clocks ligado, GPU em carga contínua, ${CARGA_MIN} min"
# Inferência do I1 pelo P2, sem pausa, com relatório a cada 30 s (quadros/s e latência)
SONDA='
import json, sys, time, numpy as np, p2
meta = json.load(open(sys.argv[1] + "/metadata.json"))
h = p2.load(meta["artifact_id"] + "-" + meta["artifact_version"])
(nome, forma), = p2.info(h)["input_shape"].items()
x = np.random.rand(*forma).astype(np.float32)
fim = time.time() + float(sys.argv[2])
while time.time() < fim:
    t0, n, lat = time.time(), 0, 0.0
    while time.time() - t0 < 30 and time.time() < fim:
        _, st = p2.infer(h, {nome: x}); n += 1; lat += st["latency_ms"]
    print(json.dumps({"t": round(time.time()), "qps": round(n / (time.time() - t0), 1),
                      "lat_ms": round(lat / max(n, 1), 2)}), flush=True)
'
SONDA_C="ods-teste-jetson-clocks-$$"
docker run -d --name "$SONDA_C" --runtime nvidia --entrypoint "" \
  -e P2_ENGINE_DIR=/opt/ods/engines -e P2_BACKEND=trt \
  -v "$I1_ENGINES_DIR:/opt/ods/engines:ro" \
  "$IMG" python3 -c "$SONDA" "/app/I1/artifacts/$I1_PACOTE" $((CARGA_MIN * SEG_POR_MIN)) >/dev/null
fase carga $((CARGA_MIN * SEG_POR_MIN + SEG_POR_MIN / 3))
docker logs "$SONDA_C" 2>&1 | grep '^{' > "$SAIDA/sonda.log" || true
docker rm -f "$SONDA_C" >/dev/null 2>&1; SONDA_C=""
eval "$(resumo_fase carga | sed 's/\([A-Z_]*\)=/C_\1=/g')"

# ---- análise --------------------------------------------------------------------------------
etapa "Resultado"
medida "Base (dinâmico, parado):      potência ${B_POT_MED} W (máx ${B_POT_MAX}) · tj ${B_TJ_MED} °C (máx ${B_TJ_MAX}) · ventoinha $(sed 's/.*: //' "$SAIDA/ventoinha-base.txt")"
medida "jetson_clocks, parado:        potência ${P_POT_MED} W (máx ${P_POT_MAX}) · tj ${P_TJ_MED} °C (máx ${P_TJ_MAX}) · ventoinha $(sed 's/.*: //' "$SAIDA/ventoinha-parada.txt")"
medida "jetson_clocks, carga contínua: potência ${C_POT_MED} W (máx ${C_POT_MAX}) · tj ${C_TJ_MED} °C (máx ${C_TJ_MAX}) · GPU ${C_GPU_MED}% · ventoinha $(sed 's/.*: //' "$SAIDA/ventoinha-carga.txt")"
read -r Q_INI Q_FIM L_INI L_FIM NJ < <(python3 - "$SAIDA/sonda.log" <<'PY'
import json, sys
v = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
if len(v) < 2: print("0 0 0 0", len(v)); sys.exit()
print(v[0]["qps"], v[-1]["qps"], v[0]["lat_ms"], v[-1]["lat_ms"], len(v))
PY
)
medida "Inferência sob carga: ${Q_INI} → ${Q_FIM} por segundo (latência ${L_INI} → ${L_FIM} ms), ${NJ} trechos de 30 s"
medida "Primeiro limite térmico passivo: ${TRIP:-?} °C (todos em limites.txt)"

if [[ -z "${TRIP:-}" ]]; then
  item J01 AVISO "temperatura máxima ${C_TJ_MAX} °C; não achei os limites térmicos do kernel para comparar"
else
  FOLGA=$(awk -v t="$TRIP" -v m="$C_TJ_MAX" 'BEGIN { printf "%.1f", t - m }')
  if awk -v f="$FOLGA" 'BEGIN { exit !(f >= 10) }'; then
    item J01 PASSOU "máx ${C_TJ_MAX} °C sob carga contínua, ${FOLGA} °C abaixo do limite passivo (${TRIP} °C)"
  elif awk -v f="$FOLGA" 'BEGIN { exit !(f > 0) }'; then
    item J01 AVISO "máx ${C_TJ_MAX} °C, só ${FOLGA} °C abaixo do limite passivo (${TRIP} °C)"
  else
    item J01 FALHOU "máx ${C_TJ_MAX} °C atingiu o limite passivo (${TRIP} °C): a placa reduziu os relógios por calor"
  fi
fi
OC_DEPOIS=$(contar_oc)
if [[ -z "$TEM_OC" ]]; then
  item J02 AVISO "o kernel não expõe contadores de sobrecorrente (oc*_event_cnt)"
elif (( OC_DEPOIS == OC_ANTES )); then
  item J02 PASSOU "nenhum evento de sobrecorrente (contador ${OC_ANTES} → ${OC_DEPOIS})"
else
  item J02 FALHOU "$((OC_DEPOIS - OC_ANTES)) evento(s) de sobrecorrente: a fonte/regulador limitou a placa"
fi
if (( NJ < 2 )); then
  item J03 FALHOU "a carga na GPU não rodou (veja docker logs / sonda.log)"
elif awk -v a="$Q_INI" -v b="$Q_FIM" 'BEGIN { exit !(b >= 0.9 * a) }'; then
  item J03 PASSOU "desempenho estável: ${Q_INI} → ${Q_FIM} inferências/s em ${CARGA_MIN} min"
else
  item J03 FALHOU "desempenho caiu: ${Q_INI} → ${Q_FIM} inferências/s (redução por calor ou energia)"
fi
KAFKA_DEPOIS=$(docker ps --filter name='^kafka$' --format '{{.Status}}' || true)
if [[ -n "$KAFKA_ANTES" && -n "$KAFKA_DEPOIS" ]]; then item J04 PASSOU "Kafka da turma de pé (${KAFKA_DEPOIS})"
elif [[ -z "$KAFKA_ANTES" ]]; then item J04 AVISO "o Kafka da turma já não estava rodando antes do teste"
else item J04 FALHOU "o Kafka da turma parou durante o teste"; fi
DPOT=$(awk -v a="$B_POT_MED" -v b="$P_POT_MED" 'BEGIN { printf "%+.1f", b - a }')
DTJ=$(awk -v a="$B_TJ_MED" -v b="$P_TJ_MED" 'BEGIN { printf "%+.1f", b - a }')
item J05 AVISO "custo de deixar ligado sem uso: ${DPOT} W e ${DTJ} °C em relação à base (informativo)"

(( FALHAS == 0 ))
