#!/usr/bin/env bash
# inf_a8.sh — build "inf_a8": I7 contínuo para o A8 da nuvem, no Kafka da nuvem (P3 / SIS-1).
#
#   ./inf_a8.sh              o mesmo que ./inf_a8.sh subir
#   ./inf_a8.sh subir        confere a placa, baixa o código, constrói o que falta (a imagem do I7 é
#                                  a mesma da build inf) e sobe o i7 lendo I7_VIDEO em laço
#   ./inf_a8.sh subir --reconstruir   reconstrói a imagem
#   ./inf_a8.sh testar       espera leituras novas do I7 no Kafka e confere: container sem reinício,
#                                  detector na GPU (-fp16), source_id, captured_at recente e o contrato
#                                  com o validador do próprio I7 → resultados/aceite-inf_a8-*.txt
#   ./inf_a8.sh i1 [QUADROS] pede ao I1 da inf_a4 detecções do VER5 (placas) por ods.i1.command
#                                  (sob demanda: o A8 não consome detecções; ver o inf_a8.env)
#   ./inf_a8.sh placas [N]   as últimas N leituras do I7 no log (padrão 20)
#   ./inf_a8.sh contar       mensagens em ods.i7.plate_read (e ods.i1.command)
#   ./inf_a8.sh log [i7]     acompanha o log do I7 (Ctrl+C para sair)
#   ./inf_a8.sh status       container, voltas do vídeo, memória, disco e Kafka
#   ./inf_a8.sh parar        derruba a build (volumes mantidos)
#
# Kafka: o da nuvem (KAFKA_BROKER do .env; o da placa só por inf_a8.local.env). O container
# "kafka" da placa tem de continuar rodando: a build confere e avisa, e nunca o para.
# Convive com a inf_a4 (A4 da nuvem): o ./ods.sh trocar de uma não derruba a outra.
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Guardar a imagem no notebook e subir de lá sem reconstruir (rodam NO NOTEBOOK):
#   ./guardar-no-notebook.sh e ./subir-do-notebook.sh [pasta]
# Guia: validacao/inf_a8/GUIA-BUILD-INF-A8.md
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=inf_a8
SEGREDOS=()
ETAPAS=("i7")
ONESHOT=(kafka-topicos)

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

TOPICOS_RE='^(ods\.i7\.plate_read|ods\.i1\.command)$'
I1_COMMAND_TOPIC=${I1_COMMAND_TOPIC:-ods.i1.command}
MAX_CONTRATO=${MAX_CONTRATO:-500}
ENGINE_I7="$ENGINES_DIR/app-plates-1.0.0"

container_de() {   # container_de <projeto> <serviço>
  docker ps -aq --filter label=com.docker.compose.project="$1" \
    --filter label=com.docker.compose.service="$2" | head -1
}
container_i7() { container_de "$PROJETO" i7; }
container_i1() { container_de ods-inf_a4 i1; }

# ---------------------------------------------------------------- conferências

checar_gpu() {
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' \
    || erro "o Docker desta placa não tem o runtime nvidia; o I7 (TensorRT) não sobe sem ele.
  Confira com: docker info | grep -i runtime"
  ok "Docker com runtime nvidia (GPU para o I7)"
}

checar_engine() {
  [[ -d "$ENGINE_I7" ]] || erro "falta a engine $ENGINE_I7 do I7 (a mesma do I1).
  Compile com: ../inf_a4/inf_a4.sh engines   (ou suba a inf_a4: ../inf_a4/inf_a4.sh)"
  ok "engine do I7: $ENGINE_I7"
}

checar_kafka_local() {
  local c=${KAFKA_LOCAL_CONTAINER:-kafka} estado
  estado=$(docker ps -a --filter name="^${c}\$" --format '{{.Status}}' || true)
  if [[ -z "$estado" ]]; then aviso "o container '$c' (Kafka da turma na placa) não existe nesta placa"
  elif [[ "$estado" == Up* ]]; then ok "Kafka da turma na placa ('$c') rodando: $estado"
  else aviso "o Kafka da turma na placa ('$c') está PARADO ($estado). Ele tem de ficar de pé.
  Avise o grupo dono; para religar: docker start $c"; fi
}

# A pasta pode não ser legível pelo usuário ods (ex.: a da SIS-2); o Docker (root) a monta.
# Lista pelo próprio Docker, só leitura, na imagem do Kafka que já está na placa.
listar_videos() {
  # --mount (e não -v): se a pasta não existir, falha em vez de criá-la como root
  docker run --rm --network none --mount "type=bind,source=$I7_VIDEO_DIR,target=/v,readonly" \
    --entrypoint ls "$KAFKA_IMG" -1 /v 2>/dev/null
}

checar_video() {
  local lista
  lista=$(listar_videos) || true
  [[ -n "$lista" ]] || erro "pasta $I7_VIDEO_DIR vazia ou ausente (a build não a cria; os vídeos do P3 vêm do ../i1/i1.sh videos)"
  grep -qx "$I7_VIDEO" <<<"$lista" \
    || erro "falta $I7_VIDEO em $I7_VIDEO_DIR (há: $(tr '\n' ' ' <<<"$lista")). Troque I7_VIDEO no inf_a8.local.env."
  ok "vídeo do I7: $I7_VIDEO_DIR/$I7_VIDEO (só leitura)"
}

livre_ram_mb() {
  local mb; mb=$(awk '/^MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  echo "$mb"
  (( mb >= 1500 )) || aviso "só ${mb} MB de memória disponível: o TensorRT do I7 pode falhar (OUT_OF_MEMORY)" >&2
}

checar_entradas() {
  checar_kafka_local
  checar_gpu
  checar_engine
  checar_video
  livre_ram_mb >/dev/null
  return 0
}

pos_subida() {
  etapa "I7 contínuo"
  echo "  vídeo $I7_VIDEO em laço (tempo real: $I7_TEMPO_REAL, pausa ${I7_PAUSA_S}s), source_id $I7_SOURCE_ID"
  echo "  → ods.i7.plate_read em $KAFKA_BROKER"
  echo "  acompanhe: ./inf_a8.sh log · leituras: ./inf_a8.sh placas · teste: ./inf_a8.sh testar"
  [[ -n "$(container_i1)" ]] || aviso "a inf_a4 não está de pé: o ./inf_a8.sh i1 não terá quem atenda (o I7 não precisa dela)"
  return 0
}

# ---------------------------------------------------------------- Kafka

kafka() { docker run --rm -i "$KAFKA_IMG" "$@"; }

# "tópico:partição:offset", uma linha por partição (uma chamada ao broker)
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

# I1 da inf_a4 (sob demanda): VER5, placas. Mesmo broker obrigatório.
pedir_i1() {   # pedir_i1 [QUADROS]
  local quadros=${1:-$INF_I1_QUADROS} c broker_i1 sid
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
  sid="inf-a8-$INF_I1_EQUIPE-$(date +%H%M%S)"
  local json="{\"action\": \"START\", \"squad\": \"$INF_I1_EQUIPE\", \"source_id\": \"$sid\", \"max_frames\": $quadros}"
  echo "$json" | kafka kafka-console-producer --bootstrap-server "$KAFKA_BROKER" --topic "$I1_COMMAND_TOPIC" 2>/dev/null \
    || erro "não consegui publicar em $I1_COMMAND_TOPIC ($KAFKA_BROKER)"
  ok "pedido ao I1 da inf_a4: $json"
  echo "  o I1 lê $INF_I1_EQUIPE.mp4 da pasta da SIS-2; detecções em ods.i1.detections (source_id $sid)"
  echo "  acompanhe: docker logs -f --tail 20 ${c:-<container i1 da inf_a4>}"
}

placas() {   # placas [N]: últimas leituras que o I7 escreveu no log
  local n=${1:-20} c; c=$(container_i7)
  [[ -n "$c" ]] || erro "o I7 desta build não está nesta placa (./inf_a8.sh subir)"
  docker logs --tail 5000 "$c" 2>&1 | grep -E '^\[ *[0-9.]+ s \| quadro|^\[P3\] (volta|fim)' | tail -"$n"
}

# ---------------------------------------------------------------- teste

declare -a RES=()
registrar() { RES+=("$1|$2|$3|$4"); }   # registrar <id> <resultado> <o quê> <detalhe>

delta() {   # delta <tópico>
  local a d
  a=$(somar "$ANTES" | awk -v t="$1" '$1 == t { print $2 }')
  d=$(somar "$DEPOIS" | awk -v t="$1" '$1 == t { print $2 }')
  echo $(( ${d:-0} - ${a:-0} ))
}

# Mensagens novas de um tópico (de cada partição, a partir do offset de ANTES) para um arquivo
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

contrato_i7() {   # contrato_i7 <arquivo>: saída do validar_i7.py na imagem do I7
  local saida
  saida=$(docker run --rm --network none --entrypoint python3 \
    -v "$ODS_DIR_APP/contrato:/p3/contrato:ro" -v "$(readlink -f "$1"):/p3/msgs.jsonl:ro" \
    "ods-i7-gpu:$I7_REF" -u /p3/contrato/validar_i7.py /p3/msgs.jsonl "$I7_SOURCE_ID" "$I7_TESTE_IDADE_MAX_S" 2>&1) || true
  grep -E '^(CONTRATO|VERSOES|IDADE|PLACAS) ' <<<"$saida" \
    || echo "CONTRATO 0 0 a validação não rodou na imagem do I7: $(tail -1 <<<"$saida" | cut -c1-160)"
}

testar() {
  etapa "Conferindo"
  aceite_conferir i7
  checar_kafka_local
  local c7; c7=$(container_i7)
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  local rel="resultados/aceite-inf_a8-$ts.txt" pasta="resultados/aceite-inf_a8-$ts"
  mkdir -p "$pasta"
  ANTES="$pasta/offsets-antes.txt"; DEPOIS="$pasta/offsets-depois.txt"
  local ram_antes restarts_antes t0
  ram_antes=$(livre_ram_mb)
  restarts_antes=$(docker inspect -f '{{.RestartCount}}' "$c7")
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  offsets_brutos > "$ANTES"
  [[ -s "$ANTES" ]] || erro "não consegui contar as mensagens em $KAFKA_BROKER"

  etapa "Esperando leituras novas do I7 (até ${I7_TESTE_ESPERA_S}s: no ritmo do vídeo, uma volta mais a pausa)"
  local limite=$((SECONDS + I7_TESTE_ESPERA_S)) n=0
  while (( SECONDS < limite )); do
    offsets_brutos > "$DEPOIS"
    n=$(delta ods.i7.plate_read)
    (( n > 0 )) && break
    sleep 15
  done
  # Mais um pouco para juntar algumas leituras (a mesma placa só volta depois da janela de repetição)
  (( n > 0 )) && { sleep 30; offsets_brutos > "$DEPOIS"; n=$(delta ods.i7.plate_read); }
  local ram_depois restarts_depois oom estado
  ram_depois=$(livre_ram_mb)
  restarts_depois=$(docker inspect -f '{{.RestartCount}}' "$c7")
  estado=$(docker inspect -f '{{.State.Status}}' "$c7")
  docker logs "$c7" > "$pasta/i7.log" 2>&1 || true
  oom=$(grep -cE 'OUT_OF_MEMORY|NvMap.*error' "$pasta/i7.log" || true)

  etapa "Lendo as leituras novas e conferindo o contrato"
  ler_novas ods.i7.plate_read "$pasta/i7.plate_read.jsonl"
  local c v t e versoes idade velhas lidas
  c=$(contrato_i7 "$pasta/i7.plate_read.jsonl")
  read -r _ v t e <<<"$(grep '^CONTRATO' <<<"$c")"
  versoes=$(sed -n 's/^VERSOES //p' <<<"$c")
  read -r _ idade velhas <<<"$(grep '^IDADE' <<<"$c" || echo "IDADE - -")"
  lidas=$(sed -n 's/^PLACAS //p' <<<"$c")
  local voltas; voltas=$(grep -c '^\[P3\] volta' "$pasta/i7.log" || true)

  # --- avaliação
  if [[ "$estado" == running ]] && (( restarts_depois == restarts_antes && oom == 0 )); then
    registrar T-I7C PASSOU "I7 contínuo, sem reinício" "running; RestartCount $restarts_antes; $voltas volta(s) no log"
  else
    registrar T-I7C FALHOU "I7 contínuo, sem reinício" "$estado; RestartCount $restarts_antes → $restarts_depois; OUT_OF_MEMORY: $oom"
  fi
  if (( n > 0 && ${t:-0} > 0 )); then registrar T-I7 PASSOU "I7 leituras ($I7_SOURCE_ID)" "$t de $n mensagens novas: $(cut -c1-80 <<<"$lidas")"
  elif (( n > 0 )); then registrar T-I7 FALHOU "I7 leituras ($I7_SOURCE_ID)" "$n mensagens novas, nenhuma com source_id $I7_SOURCE_ID"
  else registrar T-I7 FALHOU "I7 leituras ($I7_SOURCE_ID)" "nenhuma em ${I7_TESTE_ESPERA_S}s (./inf_a8.sh log)"; fi
  # Sem leituras, a versão vem da linha "Publicação: … artifact_version=…" que o I7 escreve ao abrir
  local origem_versao="das mensagens"
  if [[ -z "$versoes" || "$versoes" == - ]]; then
    versoes=$(grep -o 'artifact_version=[^ |]*' "$pasta/i7.log" | tail -1 | cut -d= -f2 || true)
    origem_versao="do log do I7"
  fi
  if [[ -n "$versoes" && "$versoes" != - && "$versoes" != *,* && "$versoes" == *-fp16* ]]; then
    registrar T-I7G PASSOU "I7 na GPU (TensorRT)" "artifact_version $versoes ($origem_versao)"
  else registrar T-I7G FALHOU "I7 na GPU (TensorRT)" "artifact_version '${versoes:-?}' $origem_versao (esperado …-fp16…)"; fi
  if (( ${t:-0} == 0 )); then registrar T-I7T AVISO "captured_at recente (A8 abre a cancela)" "sem leituras para conferir"
  elif (( ${velhas:-0} == 0 )); then registrar T-I7T PASSOU "captured_at recente (A8 abre a cancela)" "maior atraso captura→publicação ${idade} s (máximo ${I7_TESTE_IDADE_MAX_S} s)"
  else registrar T-I7T FALHOU "captured_at recente (A8 abre a cancela)" "$velhas leitura(s) com mais de ${I7_TESTE_IDADE_MAX_S} s"; fi
  if (( ${t:-0} == 0 )); then registrar T-C1 FALHOU "contrato ods.i7.plate_read (validador do I7)" "nenhuma mensagem para conferir ($e)"
  elif (( v == t )); then registrar T-C1 PASSOU "contrato ods.i7.plate_read (validador do I7)" "$v de $t válidas"
  else registrar T-C1 FALHOU "contrato ods.i7.plate_read (validador do I7)" "$v de $t válidas; 1º erro: $e"; fi

  # --- relatório
  local pa=0 f=0 a=0 linha
  for linha in "${RES[@]}"; do
    case "$(cut -d'|' -f2 <<<"$linha")" in PASSOU) pa=$((pa+1)) ;; FALHOU) f=$((f+1)) ;; *) a=$((a+1)) ;; esac
  done
  {
    echo "Teste de aceitação da build inf_a8 — $(date '+%Y-%m-%d %H:%M:%S') — $(uname -n)"
    echo "Kafka: $KAFKA_BROKER · I7 ${I7_REF:0:7}, $I7_VIDEO em laço (tempo real: $I7_TEMPO_REAL), source_id $I7_SOURCE_ID · desde $t0"
    echo "Memória disponível: $ram_antes MB → $ram_depois MB"
    echo
    for linha in "${RES[@]}"; do
      IFS='|' read -r id r oque det <<<"$linha"
      printf '%-6s %-7s %-42s %s\n' "$id" "$r" "$oque" "$det"
    done
    if (( n == 0 )); then
      echo
      echo "Sem leituras novas. Últimas linhas do I7 (progresso no vídeo, placas e motivos de não publicar):"
      grep -E '^\[P3\]|quadros a |quadros processados|^\[ *[0-9.]+ s \| quadro|Não foi possível|ERRO|Traceback' "$pasta/i7.log" | tail -12 | sed 's/^/  /'
    fi
    echo
    echo "Mensagens por tópico, todas as origens (antes → depois):"
    join -a1 -a2 -e 0 -o 0,1.2,2.2 <(somar "$ANTES") <(somar "$DEPOIS") | awk '{ printf "  %-28s %8s → %8s\n", $1, $2, $3 }'
    echo
    echo "Resumo: PASSOU $pa, FALHOU $f, AVISO $a"
  } | tee "$rel"
  echo
  echo "Relatório: $ODS_DIR_APP/$rel (mensagens e log do I7 em $pasta/)"
  (( f == 0 ))
}

# ---------------------------------------------------------------- estado

status() {
  dc ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  echo
  local c7; c7=$(container_i7)
  if [[ -n "$c7" ]]; then
    echo "I7: $(docker inspect -f '{{.State.Status}}, {{.RestartCount}} reinícios' "$c7") · vídeo $I7_VIDEO · source_id $I7_SOURCE_ID"
    echo "Voltas do vídeo: $(docker logs "$c7" 2>&1 | grep -c '^\[P3\] volta' || true)"
    echo "Últimas leituras:"
    docker logs --tail 5000 "$c7" 2>&1 | grep -E '^\[ *[0-9.]+ s \| quadro' | tail -5 | sed 's/^/  /' || echo "  nenhuma"
    docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}} · CPU {{.CPUPerc}}' "$c7" 2>/dev/null
  fi
  echo "Memória disponível: $(livre_ram_mb 2>/dev/null) MB"
  local c1; c1=$(container_i1)
  echo "I1 da inf_a4 (./inf_a8.sh i1): $([[ -n "$c1" ]] && docker inspect -f '{{.State.Status}}' "$c1" || echo 'ausente')"
  echo
  df -h /
  echo
  docker ps -a --filter name="^${KAFKA_LOCAL_CONTAINER:-kafka}\$" --format 'Kafka da turma na placa: {{.Status}}'
  echo "Kafka da build: $KAFKA_BROKER ($([[ -f inf_a8.local.env ]] && echo 'do inf_a8.local.env' || echo 'do inf_a8.env'))"
  local rel
  # shellcheck disable=SC2012
  rel=$(ls -t resultados/aceite-inf_a8-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

case "${1:-subir}" in
  i1)      shift; checar_kafka; pedir_i1 "$@" ;;
  placas)  shift; placas "$@" ;;
  contar)  contar ;;
  log)     shift; dc logs -f --tail 50 "${1:-i7}" ;;
  *)       ods_principal "$@" ;;
esac
