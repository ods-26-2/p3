#!/usr/bin/env bash
# inf_a1.sh — build "inf_a1": I8 contínuo (eventos de exemplo) para o A1 da nuvem (P3 / SIS-1).
#
#   ./inf_a1.sh              o mesmo que ./inf_a1.sh subir
#   ./inf_a1.sh subir        confere a placa, baixa o código, constrói o que falta (a imagem do I8 é
#                                  a mesma da build inf) e sobe o i8 publicando em laço
#   ./inf_a1.sh subir --reconstruir   reconstrói a imagem
#   ./inf_a1.sh testar       espera eventos novos no Kafka e confere: container sem reinício, as 4
#                                  classificações e o contrato com o validador do CONSUMIDOR (o
#                                  backend/contracts.py do próprio A1) → resultados/aceite-inf_a1-*.txt
#   ./inf_a1.sh i1 [QUADROS] pede ao I1 da inf_a4 detecções do VER1 (peças) por ods.i1.command
#                                  (sob demanda: o A1 não consome detecções)
#   ./inf_a1.sh contar       mensagens no tópico do A1 (e ods.i1.command)
#   ./inf_a1.sh log [i8]     acompanha o log do I8 (Ctrl+C para sair)
#   ./inf_a1.sh status       container, rodadas, disco e Kafka
#   ./inf_a1.sh parar        derruba a build
#
# Eventos SINTÉTICOS: o I8 não tem imagens nem manifesto real para inferir; esta build reenvia os
# eventos de exemplo do próprio I8 pelo publicador oficial dele (artifact_version p3-exemplos-i8).
# Kafka: o da nuvem (KAFKA_BROKER do .env; o da placa só por inf_a1.local.env). O container
# "kafka" da placa tem de continuar rodando: a build confere e avisa, e nunca o para.
# Convive com a inf_a2, a inf_a4 e a inf_a8 (aplicações da nuvem) no ./ods.sh trocar.
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Guardar a imagem no notebook e subir de lá (rodam NO NOTEBOOK): ./guardar-no-notebook.sh e
#   ./subir-do-notebook.sh [pasta]
# Guia: validacao/inf_a1/GUIA-BUILD-INF-A1.md
APP=inf_a1
SEGREDOS=()
ETAPAS=("i8")
ONESHOT=(kafka-topicos)

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

TOPICOS_RE="^(${I8_TOPICO//./\\.}|ods\\.i1\\.command)\$"
I1_COMMAND_TOPIC=${I1_COMMAND_TOPIC:-ods.i1.command}
MAX_CONTRATO=${MAX_CONTRATO:-500}
VERSAO_EXEMPLOS=p3-exemplos-i8

container_de() {   # container_de <projeto> <serviço>
  docker ps -aq --filter label=com.docker.compose.project="$1" \
    --filter label=com.docker.compose.service="$2" | head -1
}
container_i8() { container_de "$PROJETO" i8; }
container_i1() { container_de ods-inf_a4 i1; }

# ---------------------------------------------------------------- conferências

checar_kafka_local() {
  local c=${KAFKA_LOCAL_CONTAINER:-kafka} estado
  estado=$(docker ps -a --filter name="^${c}\$" --format '{{.Status}}' || true)
  if [[ -z "$estado" ]]; then aviso "o container '$c' (Kafka da turma na placa) não existe nesta placa"
  elif [[ "$estado" == Up* ]]; then ok "Kafka da turma na placa ('$c') rodando: $estado"
  else aviso "o Kafka da turma na placa ('$c') está PARADO ($estado). Ele tem de ficar de pé.
  Avise o grupo dono; para religar: docker start $c"; fi
}

checar_entradas() {
  checar_kafka_local
  # A taxonomia vem do clone do A1 (o preparar-codigo.sh, logo depois, clona na 1ª vez)
  local tax="$SRC_DIR/a1/shared/artifacts/defect-taxonomy/$I8_TAXONOMIA_VERSAO"
  if [[ -d "$SRC_DIR/a1" ]]; then entrada_pasta "$tax" "taxonomia do A1" "o publicador do I8 recusa sem ela"; fi
  return 0
}

pos_subida() {
  etapa "I8 contínuo"
  echo "  4 eventos de exemplo do I8 a cada ${I8_INTERVALO_S}s → $I8_TOPICO em $KAFKA_BROKER"
  echo "  (SINTÉTICOS, artifact_version $VERSAO_EXEMPLOS: o I8 não tem imagens para inferir)"
  echo "  acompanhe: ./inf_a1.sh log · teste: ./inf_a1.sh testar"
  [[ -n "$(container_i1)" ]] || aviso "a inf_a4 não está de pé: o ./inf_a1.sh i1 não terá quem atenda (o I8 não precisa dela)"
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
  printf '%-40s %s\n' TÓPICO MENSAGENS
  somar "$tmp" | awk '{ printf "%-40s %s\n", $1, $2 }'
  rm -f "$tmp"
}

# I1 da inf_a4 (sob demanda): VER1, peças. Mesmo broker obrigatório.
pedir_i1() {   # pedir_i1 [QUADROS]
  local quadros=${1:-$INF_I1_QUADROS} c broker_i1 sid fonte=""
  [[ "$quadros" =~ ^[0-9]+$ ]] || erro "QUADROS deve ser um número (recebi '$quadros')"
  c=$(container_i1)
  if [[ -z "$c" ]]; then
    aviso "o I1 da inf_a4 não está nesta placa: o pedido fica no tópico (o I1 lê só pedidos novos).
  Para subir: ../inf_a4/inf_a4.sh"
  else
    broker_i1=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | sed -n 's/^ODS_KAFKA_BROKER=//p')
    [[ -z "$broker_i1" || "$broker_i1" == "$KAFKA_BROKER" ]] \
      || erro "o I1 da inf_a4 usa o Kafka $broker_i1 e esta build, $KAFKA_BROKER: o pedido não chegaria."
  fi
  # A pasta da SIS-2 não tem o VER1.mp4: com o vídeo do P3 em VIDEO_DIR, o pedido aponta para ele
  [[ -e "$VIDEO_DIR/$INF_I1_EQUIPE.mp4" ]] && fonte=", \"source\": \"/videos-p3/$INF_I1_EQUIPE.mp4\""
  [[ -n "$fonte" ]] || aviso "sem $VIDEO_DIR/$INF_I1_EQUIPE.mp4 (../i1/i1.sh videos): o I1 procura na pasta da SIS-2, que não o tem"
  sid="inf-a1-$INF_I1_EQUIPE-$(date +%H%M%S)"
  local json="{\"action\": \"START\", \"squad\": \"$INF_I1_EQUIPE\", \"source_id\": \"$sid\", \"max_frames\": $quadros$fonte}"
  echo "$json" | kafka kafka-console-producer --bootstrap-server "$KAFKA_BROKER" --topic "$I1_COMMAND_TOPIC" 2>/dev/null \
    || erro "não consegui publicar em $I1_COMMAND_TOPIC ($KAFKA_BROKER)"
  ok "pedido ao I1 da inf_a4: $json"
  echo "  detecções em ods.i1.detections (source_id $sid); acompanhe: docker logs -f --tail 20 ${c:-<container i1 da inf_a4>}"
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

contrato_a1() {   # contrato_a1 <arquivo>: validador do A1 (consumidor) na imagem do I8
  local saida
  saida=$(docker run --rm --network none --entrypoint python \
    -v "$ODS_DIR_APP/contrato:/p3/contrato:ro" -v "$(readlink -f "$1"):/p3/msgs.jsonl:ro" \
    -v "$SRC_DIR/a1:/a1:ro" \
    "ods-i8-publisher:$I8_REF" -u /p3/contrato/validar_a1.py /p3/msgs.jsonl "$VERSAO_EXEMPLOS" 2>&1) || true
  grep -E '^(CONTRATO|CONTRATOS) ' <<<"$saida" \
    || echo "CONTRATO 0 0 a validação não rodou na imagem do I8: $(tail -1 <<<"$saida" | cut -c1-160)"
}

testar() {
  etapa "Conferindo"
  aceite_conferir i8
  checar_kafka_local
  local c8; c8=$(container_i8)
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  local rel="resultados/aceite-inf_a1-$ts.txt" pasta="resultados/aceite-inf_a1-$ts"
  mkdir -p "$pasta"
  ANTES="$pasta/offsets-antes.txt"; DEPOIS="$pasta/offsets-depois.txt"
  local restarts_antes t0
  restarts_antes=$(docker inspect -f '{{.RestartCount}}' "$c8")
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  offsets_brutos > "$ANTES"
  [[ -s "$ANTES" ]] || erro "não consegui contar as mensagens em $KAFKA_BROKER"

  etapa "Esperando uma rodada nova do I8 (até ${I8_TESTE_ESPERA_S}s; uma rodada a cada ${I8_INTERVALO_S}s)"
  local limite=$((SECONDS + I8_TESTE_ESPERA_S)) n=0
  while (( SECONDS < limite )); do
    offsets_brutos > "$DEPOIS"
    n=$(delta "$I8_TOPICO")
    (( n >= 4 )) && break
    sleep 10
  done
  offsets_brutos > "$DEPOIS"; n=$(delta "$I8_TOPICO")
  local restarts_depois estado
  restarts_depois=$(docker inspect -f '{{.RestartCount}}' "$c8")
  estado=$(docker inspect -f '{{.State.Status}}' "$c8")
  docker logs --since "$t0" "$c8" > "$pasta/i8.log" 2>&1 || true

  etapa "Lendo os eventos novos e conferindo com o validador do A1"
  ler_novas "$I8_TOPICO" "$pasta/eventos.jsonl"
  local c v t e contratos classes
  c=$(contrato_a1 "$pasta/eventos.jsonl")
  read -r _ v t e <<<"$(grep '^CONTRATO ' <<<"$c")"
  contratos=$(sed -n 's/^CONTRATOS //p' <<<"$c")
  # Classificações vistas (CONFORMING, NON_CONFORMING, ANOMALY, UNCERTAIN), pelo texto das mensagens
  classes=$(grep -oE '"(CONFORMING|NON_CONFORMING|ANOMALY|UNCERTAIN)"' "$pasta/eventos.jsonl" | tr -d '"' | sort -u | tr '\n' ' ' || true)

  # --- avaliação
  if [[ "$estado" == running ]] && (( restarts_depois == restarts_antes )); then
    registrar T-I8C PASSOU "I8 contínuo, sem reinício" "running; RestartCount $restarts_antes; $(grep -c '^\[P3\] rodada' "$pasta/i8.log" || true) rodada(s) no teste"
  else registrar T-I8C FALHOU "I8 contínuo, sem reinício" "$estado; RestartCount $restarts_antes → $restarts_depois"; fi
  if (( ${t:-0} >= 4 )); then registrar T-I8 PASSOU "I8 eventos ($VERSAO_EXEMPLOS)" "$t de $n mensagens novas; classes: ${classes:-?}"
  elif (( ${t:-0} > 0 )); then registrar T-I8 AVISO "I8 eventos ($VERSAO_EXEMPLOS)" "só $t de 4 por rodada ($n mensagens novas)"
  else registrar T-I8 FALHOU "I8 eventos ($VERSAO_EXEMPLOS)" "nenhum em ${I8_TESTE_ESPERA_S}s (./inf_a1.sh log)"; fi
  if (( ${t:-0} == 0 )); then registrar T-C1 FALHOU "contrato pelo validador do A1 (consumidor)" "nenhuma mensagem para conferir ($e)"
  elif (( v == t )); then registrar T-C1 PASSOU "contrato pelo validador do A1 (consumidor)" "$v de $t válidas ($contratos)"
  else registrar T-C1 FALHOU "contrato pelo validador do A1 (consumidor)" "$v de $t válidas; 1º erro: $e"; fi

  # --- relatório
  local pa=0 f=0 a=0 linha
  for linha in "${RES[@]}"; do
    case "$(cut -d'|' -f2 <<<"$linha")" in PASSOU) pa=$((pa+1)) ;; FALHOU) f=$((f+1)) ;; *) a=$((a+1)) ;; esac
  done
  {
    echo "Teste de aceitação da build inf_a1 — $(date '+%Y-%m-%d %H:%M:%S') — $(uname -n)"
    echo "Kafka: $KAFKA_BROKER · I8 ${I8_REF:0:7} (eventos de exemplo, SINTÉTICOS) · A1 ${A1_REF:0:7} · tópico $I8_TOPICO · desde $t0"
    echo
    for linha in "${RES[@]}"; do
      IFS='|' read -r id r oque det <<<"$linha"
      printf '%-6s %-7s %-42s %s\n' "$id" "$r" "$oque" "$det"
    done
    if (( n == 0 )); then
      echo
      echo "Sem eventos novos. Últimas linhas do I8:"
      tail -12 "$pasta/i8.log" | sed 's/^/  /'
    fi
    echo
    echo "Mensagens por tópico, todas as origens (antes → depois):"
    join -a1 -a2 -e 0 -o 0,1.2,2.2 <(somar "$ANTES") <(somar "$DEPOIS") | awk '{ printf "  %-40s %8s → %8s\n", $1, $2, $3 }'
    echo
    echo "Resumo: PASSOU $pa, FALHOU $f, AVISO $a"
  } | tee "$rel"
  echo
  echo "Relatório: $ODS_DIR_APP/$rel (eventos e log do I8 em $pasta/)"
  (( f == 0 ))
}

# ---------------------------------------------------------------- estado

status() {
  dc ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  echo
  local c8; c8=$(container_i8)
  if [[ -n "$c8" ]]; then
    echo "I8: $(docker inspect -f '{{.State.Status}}, {{.RestartCount}} reinícios' "$c8") · uma rodada a cada ${I8_INTERVALO_S}s"
    echo "Rodadas: $(docker logs "$c8" 2>&1 | grep -c '^\[P3\] rodada' || true)"
    echo "Últimas linhas do I8:"; docker logs --tail 5 "$c8" 2>&1 | sed 's/^/  /'
  fi
  local c1; c1=$(container_i1)
  echo "I1 da inf_a4 (./inf_a1.sh i1): $([[ -n "$c1" ]] && docker inspect -f '{{.State.Status}}' "$c1" || echo 'ausente')"
  echo
  df -h /
  echo
  docker ps -a --filter name="^${KAFKA_LOCAL_CONTAINER:-kafka}\$" --format 'Kafka da turma na placa: {{.Status}}'
  echo "Kafka da build: $KAFKA_BROKER ($([[ -f inf_a1.local.env ]] && echo 'do inf_a1.local.env' || echo 'do inf_a1.env'))"
  local rel
  # shellcheck disable=SC2012
  rel=$(ls -t resultados/aceite-inf_a1-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

case "${1:-subir}" in
  i1)      shift; checar_kafka; pedir_i1 "$@" ;;
  contar)  contar ;;
  log)     shift; dc logs -f --tail 50 "${1:-i8}" ;;
  *)       ods_principal "$@" ;;
esac
