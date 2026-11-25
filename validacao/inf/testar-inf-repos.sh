#!/usr/bin/env bash
# testar-inf-repos.sh — as suítes de teste dos repositórios das equipes, dentro das imagens da
# build "inf" (P3 / SIS-1).
#
# Usa exatamente a imagem que cada serviço da builds/inf/docker-compose.yml usa (lida do
# "docker compose config"), no commit fixado do inf.env. Não altera imagem nem código das
# equipes: o que a imagem não leva (pasta de testes, dados de teste, pytest) entra por volume
# do clone em SRC_DIR, no mesmo commit, ou é instalado num container descartável.
# As suítes rodam com --network none (nada vai para o Kafka), exceto a do I4, que precisa da
# rede só para instalar o pytest.
#
# Itens:
#   R-I1  suíte do I1 no serviço da build dedicada: validacao/i1/testar-i1-servico.sh (GPU)
#   R-I2  I2/tests (unittest), já dentro da imagem ods-i2
#   R-I3  I3/tests (unittest), já dentro da imagem ods-i3; dados/ do clone por volume
#   R-I4  tests/ (pytest) do clone por volume na imagem ods-i4; pytest instalado na hora
#   R-I6  o repositório não tem suíte (AVISO)
#   R-I7  o repositório não tem suíte (AVISO)
#   R-I8  comando padrão da imagem ods-i8-publisher, que é a suíte de contrato e do publicador
#   R-I9  I9/tests (unittest) do clone por volume na imagem ods-i9
#   (I5 fora da build inf desde 24/11/2026)
#
#   ./testar-inf-repos.sh                 todos
#   ./testar-inf-repos.sh --sem-i1        sem o I1 (que usa a GPU e a build builds/i1)
#   ./testar-inf-repos.sh i2 i9           só os citados (i1 i2 i3 i4 i6 i7 i8 i9)
# Resultado: validacao/inf/resultados/inf-repos-<data>.txt (+ pasta com a saída de cada suíte).
# Código de saída: 0 se nenhum item falhou.
set -euo pipefail
[[ -n "${LC_ALL:-}" ]] && export LC_ALL=C.UTF-8

AQUI="$(dirname "$(readlink -f "$0")")"
P3="$(readlink -f "$AQUI/../..")"
BUILD="$P3/builds/inf"
LIMITE_S=${LIMITE_S:-1800}

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; NC=$'\e[0m'; else V=; A=; R=; NC=; fi
etapa() { echo; echo "== $*"; }
erro()  { echo "${R}✘ $*${NC}" >&2; exit 1; }

TODOS=(i1 i2 i3 i4 i6 i7 i8 i9)
ALVOS=()
while (( $# )); do
  case "$1" in
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --sem-i1)  SEM_I1=1 ;;
    i1|i2|i3|i4|i6|i7|i8|i9) ALVOS+=("$1") ;;
    i5) erro "o I5 está fora da build inf (24/11/2026)" ;;
    *) erro "opção desconhecida: $1 (veja --help)" ;;
  esac
  shift
done
(( ${#ALVOS[@]} )) || ALVOS=("${TODOS[@]}")
if [[ -n "${SEM_I1:-}" ]]; then
  mapfile -t ALVOS < <(printf '%s\n' "${ALVOS[@]}" | grep -vx i1)
fi
quer() { printf '%s\n' "${ALVOS[@]}" | grep -qx "$1"; }

command -v docker >/dev/null || erro "docker não encontrado"
command -v python3 >/dev/null || erro "python3 não encontrado"

DATA=$(date +%Y-%m-%d-%H%M%S)
SAIDA="$AQUI/resultados/inf-repos-$DATA"
mkdir -p "$SAIDA"
REL="$SAIDA.txt"
declare -a ITENS=()
FALHAS=0
item() {
  local cor=$V
  case "$2" in FALHOU) cor=$R; FALHAS=$((FALHAS + 1)) ;; AVISO) cor=$A ;; esac
  ITENS+=("$(printf '%-5s %-6s — %s' "$1" "$2" "$3")"); echo "${cor}$1 $2${NC} — $3"
}
relatorio() {
  local cod=$?
  (( ${#ITENS[@]} )) || return "$cod"
  {
    echo "Suítes das equipes nas imagens da build inf — $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Placa: $(uname -n) · $(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo '?')"
    echo "Imagens (docker compose config de builds/inf):"
    sed 's/^/  /' "$SAIDA/imagens.txt" 2>/dev/null || true
    echo
    printf '%s\n' "${ITENS[@]}"
    echo
    echo "Resumo: $(printf '%s\n' "${ITENS[@]}" | grep -c ' PASSOU ') passou, $FALHAS falhou, $(printf '%s\n' "${ITENS[@]}" | grep -c ' AVISO ') aviso"
    echo "Saídas completas: $SAIDA/"
  } > "$REL"
  echo; cat "$REL"
  return "$cod"
}
trap relatorio EXIT

# ---- imagens da build inf --------------------------------------------------------------------
etapa "Imagens da build inf (docker compose config)"
cd "$BUILD"
ENVS=(--env-file inf.env)
[[ -f inf.local.env ]] && ENVS+=(--env-file inf.local.env)
set -a
# shellcheck source=/dev/null
source ./inf.env
# shellcheck source=/dev/null
[[ -f inf.local.env ]] && source ./inf.local.env
set +a
PERFIS=()
while read -r p; do [[ -n "$p" ]] && PERFIS+=(--profile "$p"); done < <(docker compose "${ENVS[@]}" config --profiles)
docker compose "${ENVS[@]}" "${PERFIS[@]}" config --format json > "$SAIDA/compose.json" \
  || erro "docker compose config falhou em $BUILD"
python3 - "$SAIDA/compose.json" > "$SAIDA/imagens.txt" <<'PY'
import json, sys
for nome, s in sorted(json.load(open(sys.argv[1]))["services"].items()):
    print(f"{nome} {s.get('image', '?')}")
PY
imagem() { awk -v s="$1" '$1 == s { print $2 }' "$SAIDA/imagens.txt"; }
sed 's/^/  /' "$SAIDA/imagens.txt"

# Confere a imagem; devolve 1 (e registra FALHOU) se ela não existe
tem_imagem() {   # tem_imagem <item> <imagem>
  if [[ -z "$2" ]]; then item "$1" FALHOU "serviço ausente do docker-compose.yml da inf"; return 1; fi
  docker image inspect "$2" >/dev/null 2>&1 && return 0
  item "$1" FALHOU "a imagem $2 não existe nesta placa (rode builds/inf/inf.sh subir)"; return 1
}

# Resumo de uma saída de unittest ou de pytest: "total ok falhas erros pulados"
resumo() {
  python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], errors="ignore").read()
ran = re.search(r"^Ran (\d+) tests?", t, re.M)
if ran:   # unittest
    fim = re.search(r"^(OK|FAILED)(?: \((.*)\))?\s*$", t, re.M)
    c = dict(re.findall(r"(\w+)=(\d+)", (fim.group(2) or "") if fim else ""))
    n, f, e, p = int(ran.group(1)), int(c.get("failures", 0)), int(c.get("errors", 0)), int(c.get("skipped", 0))
    print(n, n - f - e - p, f, e, p); sys.exit()
# pytest: última linha de resumo, ex. "12 passed, 1 failed, 2 skipped in 3.4s"
linhas = [l for l in t.splitlines() if re.search(r"\b(passed|failed|error|errors|no tests ran)\b.* in [0-9.]+s", l)]
c = {k: int(v) for v, k in re.findall(r"(\d+) (passed|failed|errors?|skipped|xfailed|xpassed)", linhas[-1])} if linhas else {}
ok, f = c.get("passed", 0) + c.get("xfailed", 0) + c.get("xpassed", 0), c.get("failed", 0)
e, p = c.get("error", 0) + c.get("errors", 0), c.get("skipped", 0)
print(ok + f + e + p, ok, f, e, p)
PY
}

# Roda a suíte, guarda a saída e registra o item pelo resumo
rodar_suite() {   # rodar_suite <item> <descrição> <arquivo de saída> -- <docker run ...>
  local id=$1 desc=$2 arq=$3; shift 4
  echo "  docker run $*" | cut -c1-200
  local cod=0
  timeout "$LIMITE_S" docker run --rm -e PYTHONDONTWRITEBYTECODE=1 "$@" > "$arq" 2>&1 || cod=$?
  local n ok f e p
  read -r n ok f e p < <(resumo "$arq")
  echo "  código $cod · $n testes: $ok ok, $f falha(s), $e erro(s), $p pulado(s)"
  if (( cod == 124 )); then item "$id" FALHOU "$desc: passou de ${LIMITE_S} s (veja $arq)"
  elif (( n == 0 )); then item "$id" FALHOU "$desc: a suíte não rodou (código $cod; veja $arq)"
  elif (( f + e == 0 && cod == 0 )); then item "$id" PASSOU "$desc: $n testes, $ok ok, $p pulado(s)"
  else
    local quais
    quais=$(grep -E '^(ERROR|FAIL): |^(FAILED|ERROR) [^ (]+::' "$arq" | sed -E 's/^(ERROR|FAIL): ([^ ]+).*/\2/; s/^(FAILED|ERROR) ([^ ]+).*/\2/' | head -8 | tr '\n' ' ')
    item "$id" FALHOU "$desc: $ok de $n ok, $f falha(s), $e erro(s): ${quais:-veja o arquivo}(veja $arq)"
  fi
}

# ---- I1 ----------------------------------------------------------------------------------------
if quer i1; then
  etapa "R-I1 Suíte do I1 no serviço da build dedicada (validacao/i1/testar-i1-servico.sh)"
  cod=0
  "$P3/validacao/i1/testar-i1-servico.sh" > "$SAIDA/i1.txt" 2>&1 || cod=$?
  resumo_i1=$(grep '^Resumo' "$SAIDA/i1.txt" | tail -1 || true)
  rel_i1=$(grep -o '/[^ ]*/i1-servico-[0-9-]*' "$SAIDA/i1.txt" | tail -1 || true)
  if (( cod == 0 )); then item R-I1 PASSOU "testar-i1-servico.sh: ${resumo_i1#Resumo: } (${rel_i1:-$SAIDA/i1.txt}.txt)"
  else item R-I1 FALHOU "testar-i1-servico.sh terminou com código $cod: ${resumo_i1#Resumo: } (veja $SAIDA/i1.txt)"; fi
fi

# ---- I2: os testes já estão na imagem (/app/I2/tests) -------------------------------------------
if quer i2; then
  etapa "R-I2 I2/tests (unittest) na imagem do serviço i2"
  img=$(imagem i2)
  if tem_imagem R-I2 "$img"; then
    rodar_suite R-I2 "I2/tests na $img" "$SAIDA/i2.txt" -- --network none \
      --entrypoint python "$img" -m unittest discover -s I2/tests -t I2 -v
  fi
fi

# ---- I3: testes na imagem; dados/ (imagem da quadra do A4) vem do clone ---------------------------
if quer i3; then
  etapa "R-I3 I3/tests (unittest) na imagem do serviço i3"
  img=$(imagem i3)
  if tem_imagem R-I3 "$img"; then
    [[ -d "$SRC_DIR/i3/dados" ]] || aviso_dados=" (sem $SRC_DIR/i3/dados: os testes da quadra devem falhar)"
    rodar_suite R-I3 "I3/tests na $img${aviso_dados:-}" "$SAIDA/i3.txt" -- --network none \
      -v "$SRC_DIR/i3/dados:/app/dados:ro" \
      --entrypoint python "$img" -m unittest discover -s I3/tests -t I3 -v
  fi
fi

# ---- I4: tests/ do clone; pytest não vem na imagem (instalado no container descartável) ----------
if quer i4; then
  etapa "R-I4 tests/ (pytest) na imagem do serviço i4"
  img=$(imagem i4)
  if tem_imagem R-I4 "$img"; then
    if [[ -d "$SRC_DIR/i4/tests" ]]; then
      rodar_suite R-I4 "tests/ do I4 na $img (+ pytest)" "$SAIDA/i4.txt" -- \
        -v "$SRC_DIR/i4/tests:/app/tests:ro" -w /app \
        --entrypoint sh "$img" -c \
        'pip install -q --no-cache-dir pytest >/dev/null 2>&1 || { echo "não instalei o pytest"; exit 3; }
         exec python -m pytest -p no:cacheprovider -q -rfE tests'
    else
      item R-I4 FALHOU "sem $SRC_DIR/i4/tests (rode builds/inf/preparar-codigo.sh)"
    fi
  fi
fi

# ---- I6 e I7: sem suíte no repositório -----------------------------------------------------------
quer i6 && item R-I6 AVISO "o repositório do I6 (DetectorQR) não tem suíte de testes"
quer i7 && item R-I7 AVISO "o repositório do I7 não tem suíte de testes (só scripts/consumidor_teste.py, manual)"

# ---- I8: o comando padrão da imagem do publicador é a suíte ---------------------------------------
if quer i8; then
  etapa "R-I8 Comando padrão da imagem do serviço i8 (pytest de contrato e do publicador)"
  img=$(imagem i8)
  if tem_imagem R-I8 "$img"; then
    echo "  CMD: $(docker image inspect -f '{{join .Config.Cmd " "}}' "$img" | cut -c1-160)"
    rodar_suite R-I8 "suíte do Dockerfile.publisher na $img" "$SAIDA/i8.txt" -- --network none "$img"
  fi
fi

# ---- I9: tests/ do clone (a imagem do P3 não copia os testes) --------------------------------------
if quer i9; then
  etapa "R-I9 I9/tests (unittest) na imagem do serviço i9"
  img=$(imagem i9)
  if tem_imagem R-I9 "$img"; then
    if [[ -d "$SRC_DIR/i9/I9/tests" ]]; then
      rodar_suite R-I9 "I9/tests na $img" "$SAIDA/i9.txt" -- --network none \
        -v "$SRC_DIR/i9/I9/tests:/app/tests:ro" -w /app \
        --entrypoint python "$img" -m unittest discover -s tests -t . -v
    else
      item R-I9 FALHOU "sem $SRC_DIR/i9/I9/tests (rode builds/inf/preparar-codigo.sh)"
    fi
  fi
fi

(( FALHAS == 0 ))
