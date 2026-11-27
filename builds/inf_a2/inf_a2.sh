#!/usr/bin/env bash
# inf_a2.sh — build "inf_a2": I6 contínuo para o A2 da nuvem, no Kafka da nuvem (P3 / SIS-1).
#
#   ./inf_a2.sh              o mesmo que ./inf_a2.sh subir
#   ./inf_a2.sh subir        confere a placa, baixa o código, constrói o que falta (a imagem do I6 é
#                                  a mesma da build inf), sobe o i6 e gera o vídeo do QR se faltar,
#                                  mudar ou estiver para vencer
#   ./inf_a2.sh subir --reconstruir   reconstrói a imagem
#   ./inf_a2.sh testar       espera leituras novas do I6 no Kafka e confere: container sem reinício,
#                                  source_id da catraca, o código lido é aceito pelas regras do A2,
#                                  atraso captura → publicação e o contrato com o validador do próprio
#                                  I6 → resultados/aceite-inf_a2-*.txt
#   ./inf_a2.sh qr           gera de novo o código e o vídeo do QR (ex.: depois de trocar a chave)
#   ./inf_a2.sh contar       mensagens em ods.i6.code_read
#   ./inf_a2.sh log [i6]     acompanha o log do I6 (Ctrl+C para sair)
#   ./inf_a2.sh status       container, código do QR (validade), memória, disco e Kafka
#   ./inf_a2.sh parar        derruba a build (volumes mantidos)
#
# Kafka: o da nuvem (KAFKA_BROKER do .env; o da placa só por inf_a2.local.env). O container
# "kafka" da placa tem de continuar rodando: a build confere e avisa, e nunca o para.
# Chave AES do A2: inf_a2.secrets.env (fora do Git; veja o .exemplo). Sem ele, a chave de teste do A2.
# Convive com a inf_a4 e a inf_a8 (aplicações da nuvem) no ./ods.sh trocar.
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Guardar a imagem no notebook e subir de lá sem reconstruir (rodam NO NOTEBOOK):
#   ./guardar-no-notebook.sh e ./subir-do-notebook.sh [pasta]
# Guia: validacao/inf_a2/GUIA-BUILD-INF-A2.md
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=inf_a2
SEGREDOS=()
ETAPAS=("i6")
ONESHOT=(kafka-topicos)

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

TOPICOS_RE='^(ods\.i6\.code_read)$'
MAX_CONTRATO=${MAX_CONTRATO:-500}
# Chave de teste que o A2 usa sem .env (A2Local/LiberacaoCatraca/interpreta_codigo.py)
CHAVE_TESTE_A2=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ESTADO_QR="$VIDEO_DIR/${I6_VIDEO%.*}.codigo"

container_i6() {
  docker ps -aq --filter label=com.docker.compose.project="$PROJETO" \
    --filter label=com.docker.compose.service=i6 | head -1
}

# ---------------------------------------------------------------- conferências

checar_kafka_local() {
  local c=${KAFKA_LOCAL_CONTAINER:-kafka} estado
  estado=$(docker ps -a --filter name="^${c}\$" --format '{{.Status}}' || true)
  if [[ -z "$estado" ]]; then aviso "o container '$c' (Kafka da turma na placa) não existe nesta placa"
  elif [[ "$estado" == Up* ]]; then ok "Kafka da turma na placa ('$c') rodando: $estado"
  else aviso "o Kafka da turma na placa ('$c') está PARADO ($estado). Ele tem de ficar de pé.
  Avise o grupo dono; para religar: docker start $c"; fi
}

chave_a2() {   # a chave AES do A2: do inf_a2.secrets.env, ou a de teste do próprio A2
  local k=""
  [[ -f "$APP.secrets.env" ]] && k=$(sed -n 's/^A2_AES_KEY=//p' "$APP.secrets.env" | tail -1)
  if [[ -z "$k" ]]; then echo "$CHAVE_TESTE_A2"; return 1; fi
  echo "$k"
}

checar_entradas() {
  checar_kafka_local
  command -v openssl >/dev/null || erro "falta o openssl na placa (cifra o código do QR do A2)"
  [[ -d "$VIDEO_DIR" ]] || erro "falta a pasta de vídeos $VIDEO_DIR (crie com: ../i1/i1.sh videos)"
  [[ -w "$VIDEO_DIR" ]] || erro "sem escrita em $VIDEO_DIR: o vídeo do QR não pode ser gerado (sudo chown ods:docker $VIDEO_DIR)"
  local k
  if k=$(chave_a2); then ok "chave AES do A2: do $APP.secrets.env"
  else aviso "sem A2_AES_KEY no $APP.secrets.env: uso a chave de TESTE do A2 (\"a\" × 32).
  Se o A2 da nuvem usar outra chave, ele recusa o QR (\"Código inválido\"). Pergunte à VER-2."; fi
  (( ${#k} == 32 )) || erro "A2_AES_KEY deve ter exatamente 32 caracteres (tem ${#k})"
  return 0
}

# ---------------------------------------------------------------- código e vídeo do QR

codigo() { A2_AES_KEY="$(chave_a2 || true)" python3 "$ODS_DIR_APP/codigo_a2.py" "$@"; }

# Estado do vídeo atual: "<código> <cpf_base> <intervalo_s>" em $ESTADO_QR (não tem a chave)
qr_atual() { [[ -f "$ESTADO_QR" ]] && cat "$ESTADO_QR"; }

preparar_qr() {   # preparar_qr [--forcar]
  etapa "Código e vídeo do QR ($VIDEO_DIR/$I6_VIDEO)"
  local cod base intervalo motivo="" conf agora fim
  read -r cod base intervalo <<<"$(qr_atual || true)"
  agora=$(date +%s)
  if [[ "${1:-}" == --forcar ]]; then motivo="pedido (./inf_a2.sh qr)"
  elif [[ ! -f "$VIDEO_DIR/$I6_VIDEO" || -z "${cod:-}" ]]; then motivo="vídeo ainda não gerado"
  elif [[ "$base" != "$A2_QR_CPF_BASE" || "$intervalo" != "$A2_QR_INTERVALO_S" ]]; then motivo="CPF ou intervalo mudou no .env"
  elif ! conf=$(codigo conferir "$cod" "$((agora + 86400))"); then motivo="código vencendo ou de outra chave ($conf)"
  fi
  if [[ -z "$motivo" ]]; then
    read -r _ _ fim <<<"$conf"
    ok "QR do vídeo aceito pelas regras do A2 até $(date -d "@$fim" '+%d/%m/%Y %H:%M') (CPF de teste $(codigo conferir "$cod" | awk '{print $2}'))"
    return 0
  fi
  echo "  gerando: $motivo"
  # Começa 1 h antes (relógio da nuvem um pouco atrás) e vale A2_QR_VALIDADE_DIAS
  cod=$(codigo gerar "$A2_QR_CPF_BASE" "$((agora - 3600))" "$((agora + A2_QR_VALIDADE_DIAS * 86400))") \
    || erro "não consegui gerar o código do QR (openssl?)"
  A2_QR_CODIGO=$cod dc --profile i6 run --rm -T i6-gerar-video < /dev/null \
    || erro "não consegui gerar o vídeo $VIDEO_DIR/$I6_VIDEO"
  echo "$cod $A2_QR_CPF_BASE $A2_QR_INTERVALO_S" > "$ESTADO_QR"
  ok "vídeo do QR gerado: $(codigo conferir "$cod")"
  # O I6 relê o arquivo a cada volta: o vídeo novo entra na próxima volta
}

pos_subida() {
  preparar_qr
  etapa "I6 contínuo"
  echo "  $I6_VIDEO em laço (tempo real: $I6_TEMPO_REAL, uma leitura a cada ~${A2_QR_INTERVALO_S}s), source_id $I6_SOURCE_ID"
  echo "  → ods.i6.code_read em $KAFKA_BROKER (o A2 da nuvem libera a catraca ligada ao $I6_SOURCE_ID)"
  echo "  acompanhe: ./inf_a2.sh log · teste: ./inf_a2.sh testar"
  return 0
}

# ---------------------------------------------------------------- Kafka

kafka() { docker run --rm -i "$KAFKA_IMG" "$@"; }

offsets_brutos() {
  kafka kafka-get-offsets --bootstrap-server "$KAFKA_BROKER" --topic "$TOPICOS_RE" 2>/dev/null \
    | awk -F: 'NF >= 3' | sort
}
somar() { awk -F: '{ s[$1] += $NF } END { for (t in s) print t, s[t] }' "$1" | sort; }

contar() {
  checar_kafka
  local tmp; tmp=$(mktemp); offsets_brutos > "$tmp"
  printf '%-30s %s\n' TÓPICO MENSAGENS
  somar "$tmp" | awk '{ printf "%-30s %s\n", $1, $2 }'
  rm -f "$tmp"
}

# ---------------------------------------------------------------- teste

declare -a RES=()
registrar() { RES+=("$1|$2|$3|$4"); }

delta() {
  local a d
  a=$(somar "$ANTES" | awk -v t="$1" '$1 == t { print $2 }')
  d=$(somar "$DEPOIS" | awk -v t="$1" '$1 == t { print $2 }')
  echo $(( ${d:-0} - ${a:-0} ))
}

ler_novas() {   # ler_novas <tópico> <arquivo>
  local topico=$1 arq=$2 part ini fim n
  : > "$arq"
  while IFS=: read -r _ part ini; do
    fim=$(awk -F: -v t="$topico" -v p="$part" '$1 == t && $2 == p { print $3 }' "$DEPOIS")
    n=$(( ${fim:-0} - ini ))
    (( n > 0 )) || continue
    (( n > MAX_CONTRATO )) && n=$MAX_CONTRATO
    kafka kafka-console-consumer --bootstrap-server "$KAFKA_BROKER" --topic "$topico" \
      --partition "$part" --offset "$ini" --max-messages "$n" --timeout-ms 20000 >> "$arq" 2>/dev/null || true
  done < <(awk -F: -v t="$topico" '$1 == t' "$ANTES")
}

contrato_i6() {   # contrato_i6 <arquivo>: saída do validar_i6.py na imagem do I6
  local saida
  saida=$(docker run --rm --network none --entrypoint python \
    -v "$ODS_DIR_APP/contrato:/p3/contrato:ro" -v "$(readlink -f "$1"):/p3/msgs.jsonl:ro" \
    "ods-i6:$I6_REF" -u /p3/contrato/validar_i6.py /p3/msgs.jsonl "$I6_SOURCE_ID" "$I6_TESTE_IDADE_MAX_S" 2>&1) || true
  grep -E '^(CONTRATO|IDADE|CODIGOS) ' <<<"$saida" \
    || echo "CONTRATO 0 0 a validação não rodou na imagem do I6: $(tail -1 <<<"$saida" | cut -c1-160)"
}

testar() {
  etapa "Conferindo"
  aceite_conferir i6
  checar_kafka_local
  preparar_qr
  local c6; c6=$(container_i6)
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  local rel="resultados/aceite-inf_a2-$ts.txt" pasta="resultados/aceite-inf_a2-$ts"
  mkdir -p "$pasta"
  ANTES="$pasta/offsets-antes.txt"; DEPOIS="$pasta/offsets-depois.txt"
  local restarts_antes t0 cod_atual
  restarts_antes=$(docker inspect -f '{{.RestartCount}}' "$c6")
  read -r cod_atual _ <<<"$(qr_atual || true)"
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  offsets_brutos > "$ANTES"
  [[ -s "$ANTES" ]] || erro "não consegui contar as mensagens em $KAFKA_BROKER"

  etapa "Esperando leituras novas do I6 (até ${I6_TESTE_ESPERA_S}s: uma volta do vídeo é ~${A2_QR_INTERVALO_S}s)"
  local limite=$((SECONDS + I6_TESTE_ESPERA_S)) n=0
  while (( SECONDS < limite )); do
    offsets_brutos > "$DEPOIS"
    n=$(delta ods.i6.code_read)
    (( n >= 2 )) && break
    sleep 10
  done
  offsets_brutos > "$DEPOIS"; n=$(delta ods.i6.code_read)
  local restarts_depois estado
  restarts_depois=$(docker inspect -f '{{.RestartCount}}' "$c6")
  estado=$(docker inspect -f '{{.State.Status}}' "$c6")
  docker logs --since "$t0" "$c6" > "$pasta/i6.log" 2>&1 || true

  etapa "Lendo as leituras novas e conferindo"
  ler_novas ods.i6.code_read "$pasta/i6.code_read.jsonl"
  local c v t e idade velhas codigos
  c=$(contrato_i6 "$pasta/i6.code_read.jsonl")
  read -r _ v t e <<<"$(grep '^CONTRATO' <<<"$c")"
  read -r _ idade velhas <<<"$(grep '^IDADE' <<<"$c" || echo "IDADE - -")"
  codigos=$(sed -n 's/^CODIGOS //p' <<<"$c")

  # --- avaliação
  if [[ "$estado" == running ]] && (( restarts_depois == restarts_antes )); then
    registrar T-I6C PASSOU "I6 contínuo, sem reinício" "running; RestartCount $restarts_antes"
  else registrar T-I6C FALHOU "I6 contínuo, sem reinício" "$estado; RestartCount $restarts_antes → $restarts_depois"; fi
  if (( n > 0 && ${t:-0} > 0 )); then registrar T-I6 PASSOU "I6 leituras ($I6_SOURCE_ID)" "$t de $n mensagens novas"
  elif (( n > 0 )); then registrar T-I6 FALHOU "I6 leituras ($I6_SOURCE_ID)" "$n mensagens novas, nenhuma com source_id $I6_SOURCE_ID"
  else registrar T-I6 FALHOU "I6 leituras ($I6_SOURCE_ID)" "nenhuma em ${I6_TESTE_ESPERA_S}s (./inf_a2.sh log)"; fi
  local conf
  if (( ${t:-0} == 0 )); then registrar T-I6Q AVISO "QR aceito pelas regras do A2" "sem leituras para conferir"
  elif [[ "$codigos" != *,* ]] && conf=$(codigo conferir "$codigos"); then
    registrar T-I6Q PASSOU "QR aceito pelas regras do A2" "CPF $(awk '{print $2}' <<<"$conf"), válido até $(date -d "@$(awk '{print $3}' <<<"$conf")" '+%d/%m/%Y')$([[ "$codigos" == "$cod_atual" ]] || echo '; ATENÇÃO: não é o código do vídeo atual')"
  else registrar T-I6Q FALHOU "QR aceito pelas regras do A2" "lido '$codigos': ${conf:-mais de um código}"; fi
  if (( ${t:-0} == 0 )); then registrar T-I6T AVISO "captura → publicação (A2: até ${I6_TESTE_IDADE_MAX_S} s)" "sem leituras"
  elif (( ${velhas:-0} == 0 )); then registrar T-I6T PASSOU "captura → publicação (A2: até ${I6_TESTE_IDADE_MAX_S} s)" "maior atraso ${idade} s"
  else registrar T-I6T FALHOU "captura → publicação (A2: até ${I6_TESTE_IDADE_MAX_S} s)" "$velhas leitura(s) acima; maior ${idade} s"; fi
  if (( ${t:-0} == 0 )); then registrar T-C1 FALHOU "contrato ods.i6.code_read (validador do I6)" "nenhuma mensagem para conferir ($e)"
  elif (( v == t )); then registrar T-C1 PASSOU "contrato ods.i6.code_read (validador do I6)" "$v de $t válidas"
  else registrar T-C1 FALHOU "contrato ods.i6.code_read (validador do I6)" "$v de $t válidas; 1º erro: $e"; fi

  # --- relatório
  local pa=0 f=0 a=0 linha
  for linha in "${RES[@]}"; do
    case "$(cut -d'|' -f2 <<<"$linha")" in PASSOU) pa=$((pa+1)) ;; FALHOU) f=$((f+1)) ;; *) a=$((a+1)) ;; esac
  done
  {
    echo "Teste de aceitação da build inf_a2 — $(date '+%Y-%m-%d %H:%M:%S') — $(uname -n)"
    echo "Kafka: $KAFKA_BROKER · I6 ${I6_REF:0:7}, $I6_VIDEO em laço (tempo real: $I6_TEMPO_REAL), source_id $I6_SOURCE_ID · desde $t0"
    echo "Chave AES: $(chave_a2 >/dev/null && echo "do $APP.secrets.env" || echo 'a de teste do A2 ("a" × 32)')"
    echo
    for linha in "${RES[@]}"; do
      IFS='|' read -r id r oque det <<<"$linha"
      printf '%-6s %-7s %-42s %s\n' "$id" "$r" "$oque" "$det"
    done
    if (( n == 0 )); then
      echo
      echo "Sem leituras novas. Últimas linhas do I6:"
      tail -12 "$pasta/i6.log" | sed 's/^/  /'
    fi
    echo
    echo "Mensagens por tópico, todas as origens (antes → depois):"
    join -a1 -a2 -e 0 -o 0,1.2,2.2 <(somar "$ANTES") <(somar "$DEPOIS") | awk '{ printf "  %-28s %8s → %8s\n", $1, $2, $3 }'
    echo
    echo "O teste confere a leitura do QR e as regras de validade do A2 (sem o A2). A catraca e a foto do"
    echo "S4 são do A2 da nuvem: a decisão aparece no log dele (\"Código válido.\" / \"Código inválido.\")."
    echo
    echo "Resumo: PASSOU $pa, FALHOU $f, AVISO $a"
  } | tee "$rel"
  echo
  echo "Relatório: $ODS_DIR_APP/$rel (mensagens e log do I6 em $pasta/)"
  (( f == 0 ))
}

# ---------------------------------------------------------------- estado

status() {
  dc ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  echo
  local c6; c6=$(container_i6)
  if [[ -n "$c6" ]]; then
    echo "I6: $(docker inspect -f '{{.State.Status}}, {{.RestartCount}} reinícios' "$c6") · vídeo $I6_VIDEO · source_id $I6_SOURCE_ID"
    docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}} · CPU {{.CPUPerc}}' "$c6" 2>/dev/null
    echo "Últimas linhas do I6:"; docker logs --tail 5 "$c6" 2>&1 | sed 's/^/  /'
  fi
  local cod
  read -r cod _ <<<"$(qr_atual || true)"
  if [[ -n "${cod:-}" ]]; then echo "QR do vídeo: $(codigo conferir "$cod" || true)"
  else echo "QR do vídeo: ainda não gerado (./inf_a2.sh qr)"; fi
  echo
  df -h /
  echo
  docker ps -a --filter name="^${KAFKA_LOCAL_CONTAINER:-kafka}\$" --format 'Kafka da turma na placa: {{.Status}}'
  echo "Kafka da build: $KAFKA_BROKER ($([[ -f inf_a2.local.env ]] && echo 'do inf_a2.local.env' || echo 'do inf_a2.env'))"
  local rel
  # shellcheck disable=SC2012
  rel=$(ls -t resultados/aceite-inf_a2-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

case "${1:-subir}" in
  qr)      checar_entradas; preparar_qr --forcar ;;
  contar)  contar ;;
  log)     shift; dc logs -f --tail 50 "${1:-i6}" ;;
  *)       ods_principal "$@" ;;
esac
