# fluxo-comum.sh — funções dos scripts validacao/<app>/validar-<app>-fluxo.sh (P3 / SIS-1).
# Não é executado sozinho: o script da aplicação define APP e faz "source" deste arquivo.
#
#   req <nome> <código esperado> <método> <url> [json] [token]   pedido HTTP; corpo em $TMP
#   campo <expressão python sobre d>                             lê o JSON do último pedido
#   confere <nome> <expressão python sobre d>                    OK/FALHA conforme a expressão
#   fim                                                          resultado e código de saída
#
# Convenções (validacao/README.md): linhas OK / FALHA / AVISO; saída = número de falhas;
# dados de teste fictícios e apagados no fim, mesmo se o script for interrompido.

: "${APP:?defina APP antes de carregar fluxo-comum.sh}"
RAIZ=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)
SAIDA="$RAIZ/validacao/$APP/evidencias/$APP-fluxo-$(date +%F-%H%M).txt"
mkdir -p "$(dirname "$SAIDA")"
TMP=$(mktemp)
falhas=0
trap 'rm -f "$TMP"' EXIT

log()   { echo "$*" | tee -a "$SAIDA"; }
ok()    { log "OK    $*"; }
falha() { log "FALHA $*"; falhas=$((falhas + 1)); }
aviso() { log "AVISO $*"; }

req() {   # req <nome> <esperado> <método> <url> [json] [token]
  local h=(-H "Accept: application/json") codigo
  [[ -n "${5:-}" ]] && h+=(-H "Content-Type: application/json")
  [[ -n "${6:-}" ]] && h+=(-H "Authorization: Bearer $6")
  codigo=$(curl -s -m 30 -o "$TMP" -w '%{http_code}' -X "$3" "$4" "${h[@]}" ${5:+-d "$5"})
  if [[ "$codigo" == "$2" ]]; then ok "$1 (http $codigo)"; return 0; fi
  falha "$1 (esperado $2, veio $codigo) $(head -c 200 "$TMP")"
  return 1
}

campo() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$TMP" "$1" 2>/dev/null; }

confere() {   # confere <nome> <expressão python sobre d que deve ser verdadeira>
  if [[ "$(campo "bool($2)")" == True ]]; then ok "$1"; else falha "$1 ($(head -c 200 "$TMP"))"; fi
}

segredo() { grep -E "^$1=" "$RAIZ/builds/$APP/$APP.secrets.env" 2>/dev/null | cut -d= -f2-; }

fim() {
  if (( falhas == 0 )); then log "RESULTADO: FUNCIONA (fluxo do $APP)"; else log "RESULTADO: $falhas falha(s)"; fi
  log "Evidência: $SAIDA"
  exit "$falhas"
}

log "== $APP fluxo $(date '+%F %T') — $(uname -n) =="
