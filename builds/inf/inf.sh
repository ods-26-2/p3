#!/usr/bin/env bash
# inf.sh — build "inf": todas as inferências (I1–I9) da placa (P3 / SIS-1).
#
# Desde 27/11/2026 a inf roda SOBRE as builds das aplicações da nuvem (o ../ods.sh trocar inf sobe
# todas antes): inf_a4 (I1 + I2), inf_a1 (I8 contínuo), inf_a2 (I6 contínuo), inf_a8 (I7 contínuo).
# Aqui ficam o I9 contínuo e o I3 da quadra de teste (sob demanda).
#
#   ./inf.sh               o mesmo que ./inf.sh subir
#   ./inf.sh subir         confere a placa e as builds da nuvem, baixa o código, constrói o que
#                          falta (em etapas, com limpeza) e sobe o contínuo daqui: i9
#   ./inf.sh subir --reconstruir   reconstrói as imagens daqui
#   ./inf.sh i1 [EQUIPE] [QUADROS] pede detecções ao I1 da inf_a4 por ods.i1.command
#                          (padrão: INF_I1_EQUIPE e INF_I1_QUADROS do inf.env; equipes do I1:
#                          VER5 placas, VER3/VER6 EPI, VER1 indústria, INV1 esporte)
#   ./inf.sh i3            calibração da quadra de teste → ods.i3.calibration + ods.artifact.published
#   (I6, I7 e I8 são os contínuos da inf_a2, da inf_a8 e da inf_a1: ../inf_aX/inf_aX.sh status)
#   (I4 fora da build desde 27/11/2026 e I5 desde 24/11/2026: ver o docker-compose.yml)
#   ./inf.sh contar        mensagens por tópico das inferências
#   ./inf.sh testar        dispara I1 e I3, espera as mensagens novas de I2, I6, I7, I8 e I9 e
#                          confere cada tópico → resultados/aceite-inf-*.txt
#   ./inf.sh log <serviço> acompanha o log de um serviço daqui (Ctrl+C para sair)
#   ./inf.sh status        containers daqui e das builds da nuvem, memória, disco e Kafka
#   ./inf.sh parar         derruba só esta build (as da nuvem continuam de pé)
#
# O I1 permanente (builds/i1) fica parado.
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=inf
SEGREDOS=()
# I5 fora (24/11/2026), I4 fora (27/11/2026): para voltar, ("i3 i9 i4-video" "i4-server" "i4")
# I2 é o da inf_a4; I6, I7 e I8, os da inf_a2, inf_a8 e inf_a1 (27/11/2026)
ETAPAS=("i3 i9")
ONESHOT=(kafka-topicos)

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

TOPICOS_RE='^(ods\.i[0-9]\..*|ods\.p5\.audio_chunk|ods\.artifact\.published|ods\.industria\.defeito_classificado)$'

# ---------------------------------------------------------------- I1 e I2 (build inf_a4)

BASE_PROJETO=ods-inf_a4
container_de() {   # container_de <projeto> <serviço>
  docker ps -aq --filter label=com.docker.compose.project="$1" \
    --filter label=com.docker.compose.service="$2" | head -1
}
container_i1() { container_de "$BASE_PROJETO" i1; }
container_i2() { container_de "$BASE_PROJETO" i2; }

# O I1 e o I2 são os da inf_a4 (27/11/2026): de pé e no MESMO broker. O I1 permanente (builds/i1)
# no mesmo broker seria um segundo orquestrador (a inf_a4 já recusa subir com ele).
checar_i1() {
  local c estado broker_i1 c2 cp
  c=$(container_i1)
  if [[ -z "$c" ]]; then
    aviso "o I1 da inf_a4 não está nesta placa: I9 sobe, mas fica sem detecções.
  Para subir: ../inf_a4/inf_a4.sh  (ou ../ods.sh trocar inf, que sobe as duas)"
    return 0
  fi
  estado=$(docker inspect -f '{{.State.Status}}' "$c")
  [[ "$estado" == running ]] || aviso "o I1 da inf_a4 está $estado. Para subir: ../inf_a4/inf_a4.sh"
  broker_i1=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | sed -n 's/^ODS_KAFKA_BROKER=//p')
  if [[ -n "$broker_i1" && "$broker_i1" != "$KAFKA_BROKER" ]]; then
    erro "o I1 da inf_a4 usa o Kafka $broker_i1 e esta build, $KAFKA_BROKER: os pedidos não chegariam.
  Use o mesmo broker nas duas (inf.local.env aqui, ou inf_a4.local.env em ../inf_a4)."
  fi
  ok "I1 da inf_a4 $estado, no mesmo Kafka ($KAFKA_BROKER)"
  c2=$(container_i2)
  if [[ -n "$c2" && "$(docker inspect -f '{{.State.Status}}' "$c2")" == running ]]; then ok "I2 da inf_a4 rodando"
  else aviso "o I2 da inf_a4 não está rodando: ods.i2.tracks fica parado (../inf_a4/inf_a4.sh)"; fi
  cp=$(container_de ods-i1 i1)
  [[ -z "$cp" || "$(docker inspect -f '{{.State.Status}}' "$cp")" != running ]] \
    || aviso "o I1 permanente (builds/i1) também está de pé: pare-o (../i1/i1.sh parar), são dois orquestradores"
  return 0
}

# I6, I7 e I8: os contínuos das builds da nuvem (27/11/2026). build|serviço|o que faz
NUVEM_SERVICOS=("inf_a2|i6|ods.i6.code_read|I6 QR do A2" "inf_a8|i7|ods.i7.plate_read|I7 placas do A8"
                "inf_a1|i8|ods.industria.defeito_classificado|I8 peças do A1")
# Tópicos dos contínuos que o checar_nuvem achou rodando (o teste só espera por esses)
NUVEM_RODANDO=()

# Confere um contínuo de outra build: de pé e no MESMO broker (procura o endereço em qualquer
# variável KAFKA* do container). Devolve 1 se não estiver rodando.
checar_continuo() {   # checar_continuo <build> <serviço> <descrição>
  local c estado
  c=$(container_de "ods-$1" "$2")
  if [[ -z "$c" ]]; then
    aviso "$3: a build $1 não está nesta placa (../$1/$1.sh, ou ../ods.sh trocar inf, que sobe todas)"
    return 1
  fi
  estado=$(docker inspect -f '{{.State.Status}}' "$c")
  if [[ "$estado" != running ]]; then aviso "$3 ($1) está $estado: ../$1/$1.sh"; return 1; fi
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | grep -E '^KAFKA[A-Z_]*=' \
    | grep -qF "$KAFKA_BROKER" \
    || aviso "$3 ($1) não usa o Kafka $KAFKA_BROKER: as mensagens dele não aparecem na contagem daqui"
  ok "$3 ($1) rodando"
}

checar_nuvem() {
  local s b sv tp d
  NUVEM_RODANDO=()
  for s in "${NUVEM_SERVICOS[@]}"; do
    IFS='|' read -r b sv tp d <<<"$s"
    if checar_continuo "$b" "$sv" "$d"; then NUVEM_RODANDO+=("$tp"); fi
  done
  return 0
}

# ---------------------------------------------------------------- conferências

checar_entradas() {
  checar_i1
  checar_nuvem
  [[ -d "$VIDEO_DIR" ]] || aviso "falta a pasta $VIDEO_DIR (vídeos do P3 pedidos ao I1). Rode antes: ../i1/i1.sh videos"
  # I4 e I5 fora: os clones e as entradas deles não são conferidos
  livre_ram_mb >/dev/null
  return 0
}

livre_ram_mb() {
  local mb; mb=$(awk '/^MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  echo "$mb"
  # Com o I1 e o I7 (TensorRT), o Kafka e os contínuos, a placa de 7,4 GB fica no limite.
  (( mb >= 1500 )) || aviso "só ${mb} MB de memória disponível: o TensorRT do I1 pode falhar (OUT_OF_MEMORY)" >&2
}

# ---------------------------------------------------------------- depois do "up"

pos_subida() {
  echo
  echo "I9 de pé. I1/I2 (inf_a4), I6 (inf_a2), I7 (inf_a8) e I8 (inf_a1) são das builds da nuvem."
  echo "Para disparar: ./inf.sh i1 | i3 · tudo de uma vez, conferindo os tópicos: ./inf.sh testar"
}

# ---------------------------------------------------------------- disparos

kafka() { docker run --rm -i "$KAFKA_IMG" "$@"; }

pedir_i1() {
  local equipe=${1:-$INF_I1_EQUIPE} quadros=${2:-$INF_I1_QUADROS} sid=${3:-}
  [[ "$quadros" =~ ^[0-9]+$ ]] || erro "QUADROS deve ser um número (recebi '$quadros')"
  sid=${sid:-inf-$equipe-$(date +%H%M%S)}
  # O I1 da inf_a4 procura <EQUIPE>.mp4 na pasta da SIS-2, que não tem todas as equipes (ex.: VER3).
  # Com o vídeo do P3 em VIDEO_DIR (../i1/i1.sh videos), o pedido aponta para ele (/videos-p3 no I1).
  local fonte=""
  [[ -e "$VIDEO_DIR/$equipe.mp4" ]] && fonte=", \"source\": \"/videos-p3/$equipe.mp4\""
  local json="{\"action\": \"START\", \"squad\": \"$equipe\", \"source_id\": \"$sid\", \"max_frames\": $quadros$fonte}"
  [[ -n "$(container_i1)" ]] || aviso "o I1 da inf_a4 não está nesta placa: o pedido fica no tópico (o I1 lê só pedidos novos)"
  echo "$json" | kafka kafka-console-producer --bootstrap-server "$KAFKA_BROKER" --topic "$I1_COMMAND_TOPIC" 2>/dev/null \
    || erro "não consegui publicar em $I1_COMMAND_TOPIC ($KAFKA_BROKER)"
  ok "pedido ao I1: $json"
  local c; c=$(container_i1)
  echo "  acompanhe: docker logs -f --tail 20 ${c:-<container do i1>}"
}

# Entrada vazia (< /dev/null): com -T a entrada deixa de ser terminal, e o I3 (--linhas) passa a ler
# um csv opcional do stdin até o fim; sem o /dev/null ele esperava o teclado para sempre (Jetson, 24/11).
rodar() {   # rodar <perfil> <serviço>
  dc --profile "$1" run --rm -T "$2" < /dev/null
}

# ---------------------------------------------------------------- contagem por tópico

# Uma chamada ao broker para todos os tópicos: "tópico total" (soma das partições), um por linha.
offsets() {
  kafka kafka-get-offsets --bootstrap-server "$KAFKA_BROKER" --topic "$TOPICOS_RE" 2>/dev/null \
    | awk -F: 'NF >= 3 { s[$1] += $NF } END { for (t in s) print t, s[t] }' | sort
}

contar() {
  checar_kafka
  printf '%-40s %s\n' TÓPICO MENSAGENS
  offsets | awk '{ printf "%-40s %s\n", $1, $2 }'
}

# ---------------------------------------------------------------- teste

# Resultado de cada item: PASSOU, FALHOU ou AVISO, com o motivo.
declare -a RES=()
registrar() { RES+=("$1|$2|$3|$4"); }   # registrar <id> <resultado> <o quê> <detalhe>

delta() {   # delta <tópico>: mensagens novas entre as duas contagens
  local a d
  a=$(awk -v t="$1" '$1 == t { print $2 }' "$ANTES"); d=$(awk -v t="$1" '$1 == t { print $2 }' "$DEPOIS")
  echo $(( ${d:-0} - ${a:-0} ))
}

esperar_topicos() {   # esperar_topicos <segundos> <tópico>...: até todos terem mensagem nova
  local limite=$((SECONDS + $1)) t falta; shift
  while (( SECONDS < limite )); do
    offsets > "$DEPOIS"
    falta=()
    for t in "$@"; do (( $(delta "$t") > 0 )) || falta+=("$t"); done
    (( ${#falta[@]} )) || return 0
    echo "  esperando: ${falta[*]} ($(( limite - SECONDS )) s)"
    sleep 15
  done
  return 1
}

testar() {
  etapa "Conferindo"
  # I5 fora: voltar a conferir o i5 aqui
  # I2 fora (27/11/2026): o da inf_a4, conferido no checar_i1
  # I4 fora (27/11/2026): aceite_conferir i4-server i4 i6 i9
  aceite_conferir i9
  checar_i1
  checar_nuvem
  local c1; c1=$(container_i1)
  [[ -n "$c1" && "$(docker inspect -f '{{.State.Status}}' "$c1")" == running ]] \
    || erro "o I1 da inf_a4 não está rodando; suba com ../inf_a4/inf_a4.sh antes do teste"
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  local rel="resultados/aceite-inf-$ts.txt"
  # Contagens em resultados/ (o trap de saída é da lib); apagadas no fim
  ANTES=resultados/.offsets-antes; DEPOIS=resultados/.offsets-depois
  local ram_antes restarts_antes t0
  ram_antes=$(livre_ram_mb)
  restarts_antes=$(docker inspect -f '{{.RestartCount}}' "$c1")
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  offsets > "$ANTES"
  [[ -s "$ANTES" ]] || erro "não consegui contar as mensagens em $KAFKA_BROKER"

  etapa "Disparos"
  pedir_i1 "$INF_I1_EQUIPE" "$INF_I1_QUADROS" "inf-teste-$ts"
  local cod_i3=0
  echo "-- I3";  rodar i3 i3  || cod_i3=$?
  # I5 fora: echo "-- I5 (áudio como P5)"; rodar i5 i5-audio || cod_i5=$?
  # I4 fora: echo "-- I4 (vídeo como webcam)"; rodar i4 i4-video || cod_i4=$?

  # I6, I7 e I8 publicam sozinhos (builds da nuvem): só esperamos as mensagens novas, juntas
  etapa "Esperando I1/I2/I9 e os contínuos da nuvem (até ${INF_ESPERA_NUVEM_S:-420} s)"
  # Só os contínuos que estão rodando: build ausente já vira FALHOU sem gastar a espera
  esperar_topicos "${INF_ESPERA_NUVEM_S:-420}" ods.i1.detections ods.i2.tracks ods.i9.ppe_compliance \
    "${NUVEM_RODANDO[@]}" || true
  # Prova de TensorRT do I7 da inf_a8: a versão do detector termina em -fp16 (em CPU seria -fp32)
  local versao_i7 c7
  c7=$(container_de ods-inf_a8 i7)
  versao_i7=$( [[ -n "$c7" ]] && docker logs --tail 3000 "$c7" 2>&1 | grep -o 'artifact_version=[^ |]*' | tail -1 | cut -d= -f2 || true)
  offsets > "$DEPOIS"
  local ram_depois restarts_depois oom
  ram_depois=$(livre_ram_mb)
  restarts_depois=$(docker inspect -f '{{.RestartCount}}' "$c1")
  oom=$(docker logs --since "$t0" "$c1" 2>&1 | grep -c 'OUT_OF_MEMORY' || true)

  # --- avaliação
  local d
  d=$(delta ods.i1.detections)
  if (( d > 0 )); then registrar T-I1 PASSOU "I1 detecções ($INF_I1_EQUIPE)" "$d mensagens"
  else registrar T-I1 FALHOU "I1 detecções ($INF_I1_EQUIPE)" "nenhuma; veja docker logs $c1"; fi
  if (( restarts_depois == restarts_antes && oom == 0 )); then registrar T-I1M PASSOU "I1 sem reinício nem OUT_OF_MEMORY" "RestartCount $restarts_antes"
  else registrar T-I1M FALHOU "I1 sem reinício nem OUT_OF_MEMORY" "RestartCount $restarts_antes → $restarts_depois; OUT_OF_MEMORY: $oom"; fi
  d=$(delta ods.i2.tracks)
  if (( d > 0 )); then registrar T-I2 PASSOU "I2 trilhas" "$d mensagens"
  else registrar T-I2 FALHOU "I2 trilhas" "nenhuma (../inf_a4/inf_a4.sh log i2)"; fi
  d=$(delta ods.artifact.published)
  if (( cod_i3 == 0 && d > 0 )); then registrar T-I3 PASSOU "I3 calibração anunciada" "artifact.published +$d, calibration +$(delta ods.i3.calibration)"
  else registrar T-I3 FALHOU "I3 calibração anunciada" "código $cod_i3, artifact.published +$d"; fi
  # I4 fora da build (27/11/2026): sem disparo nem conferência
  registrar T-I4 AVISO "I4 sinais" "I4 fora da build inf (comentado no docker-compose.yml)"
  # d=$(delta ods.i4.sign)
  # if (( cod_i4 != 0 )); then registrar T-I4 FALHOU "I4 sinais" "envio do vídeo terminou com código $cod_i4"
  # elif (( d > 0 )); then registrar T-I4 PASSOU "I4 sinais" "sign +$d, keypoints +$(delta ods.i4.keypoints), facial_marker +$(delta ods.i4.facial_marker)"
  # elif (( $(delta ods.i4.keypoints) > 0 )); then registrar T-I4 AVISO "I4 sinais" "sem sinal reconhecido; keypoints +$(delta ods.i4.keypoints)"
  # else registrar T-I4 FALHOU "I4 sinais" "nada publicado (dc logs i4 i4-server)"; fi
  # I5 fora da build (24/11/2026): sem disparo nem conferência
  registrar T-I5 AVISO "I5 transcrição" "I5 fora da build inf (comentado no docker-compose.yml)"
  # d=$(delta ods.i5.transcript)
  # if (( cod_i5 != 0 )); then registrar T-I5 FALHOU "I5 transcrição" "envio do áudio terminou com código $cod_i5"
  # elif (( d > 0 )); then registrar T-I5 PASSOU "I5 transcrição" "$d mensagens (audio_chunk +$(delta ods.p5.audio_chunk))"
  # elif [[ "$I5_MODO" == wake-word ]]; then registrar T-I5 AVISO "I5 transcrição" "nenhuma; modo wake-word: o áudio diz \"lexie\"?"
  # else registrar T-I5 FALHOU "I5 transcrição" "nenhuma (dc logs i5)"; fi
  # I6, I7 e I8: contínuos das builds da nuvem
  d=$(delta ods.i6.code_read)
  if (( d > 0 )); then registrar T-I6 PASSOU "I6 QR (inf_a2)" "$d leituras"
  else registrar T-I6 FALHOU "I6 QR (inf_a2)" "nenhuma leitura (../inf_a2/inf_a2.sh status)"; fi
  d=$(delta ods.i7.plate_read)
  if (( d == 0 )); then registrar T-I7 FALHOU "I7 placas (inf_a8, GPU)" "nenhuma leitura (../inf_a8/inf_a8.sh status)"
  elif [[ "$versao_i7" != *-fp16* ]]; then registrar T-I7 FALHOU "I7 placas (inf_a8, GPU)" "$d leituras, mas não em TensorRT (artifact_version=${versao_i7:-?})"
  else registrar T-I7 PASSOU "I7 placas (inf_a8, GPU)" "$d leituras ($versao_i7)"; fi
  d=$(delta ods.industria.defeito_classificado)
  if (( d > 0 )); then registrar T-I8 PASSOU "I8 eventos (inf_a1)" "+$d (eventos de exemplo do I8)"
  else registrar T-I8 FALHOU "I8 eventos (inf_a1)" "nenhum (../inf_a1/inf_a1.sh status)"; fi
  d=$(delta ods.i9.ppe_compliance)
  if (( d > 0 )); then registrar T-I9 PASSOU "I9 conformidade de EPI" "$d mensagens"
  elif [[ "$INF_I1_EQUIPE" != VER3 && "$INF_I1_EQUIPE" != VER6 ]]; then registrar T-I9 AVISO "I9 conformidade de EPI" "nenhuma; o I1 rodou $INF_I1_EQUIPE, sem classes de EPI"
  else registrar T-I9 FALHOU "I9 conformidade de EPI" "nenhuma (dc logs i9)"; fi

  # --- relatório
  local p=0 f=0 a=0 linha
  for linha in "${RES[@]}"; do
    case "$(cut -d'|' -f2 <<<"$linha")" in PASSOU) p=$((p+1)) ;; FALHOU) f=$((f+1)) ;; *) a=$((a+1)) ;; esac
  done
  {
    echo "Teste de aceitação da build inf — $(date '+%Y-%m-%d %H:%M:%S') — $(uname -n)"
    echo "Kafka: $KAFKA_BROKER · I1: $INF_I1_EQUIPE, $INF_I1_QUADROS quadros · memória disponível: $ram_antes MB → $ram_depois MB"
    echo
    for linha in "${RES[@]}"; do
      IFS='|' read -r id r oque det <<<"$linha"
      printf '%-6s %-7s %-34s %s\n' "$id" "$r" "$oque" "$det"
    done
    echo
    echo "Mensagens por tópico (antes → depois):"
    join -a1 -a2 -e 0 -o 0,1.2,2.2 "$ANTES" "$DEPOIS" | awk '{ printf "  %-38s %8s → %8s\n", $1, $2, $3 }'
    echo
    echo "Resumo: PASSOU $p, FALHOU $f, AVISO $a"
  } | tee "$rel"
  rm -f "$ANTES" "$DEPOIS"
  echo
  echo "Relatório: $ODS_DIR_APP/$rel"
  (( f == 0 ))
}

# ---------------------------------------------------------------- status

status() {
  carregar_perfis
  dc "${PERFIS[@]}" ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  echo
  local c1; c1=$(container_i1)
  if [[ -n "$c1" ]]; then
    echo "I1 (inf_a4): $(docker inspect -f '{{.State.Status}}, {{.RestartCount}} reinícios' "$c1")"
  else
    echo "I1 (inf_a4): ausente (../inf_a4/inf_a4.sh)"
  fi
  local c2; c2=$(container_i2)
  echo "I2 (inf_a4): $([[ -n "$c2" ]] && docker inspect -f '{{.State.Status}}' "$c2" || echo 'ausente')"
  local s b sv tp d c
  for s in "${NUVEM_SERVICOS[@]}"; do
    IFS='|' read -r b sv tp d <<<"$s"
    c=$(container_de "ods-$b" "$sv")
    echo "$d ($b): $([[ -n "$c" ]] && docker inspect -f '{{.State.Status}}, {{.RestartCount}} reinícios' "$c" || echo 'ausente')"
  done
  local ids
  mapfile -t ids < <(for p in ods-inf ods-inf_a4 ods-inf_a1 ods-inf_a2 ods-inf_a8; do
    docker ps -q --filter label=com.docker.compose.project="$p"; done)
  (( ${#ids[@]} )) && docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}}' "${ids[@]}" 2>/dev/null
  echo "Memória disponível: $(livre_ram_mb 2>/dev/null) MB"
  echo
  df -h /
  echo
  echo "Kafka: $KAFKA_BROKER ($([[ -f inf.local.env ]] && echo 'do inf.local.env' || echo 'do inf.env'))"
  local rel; rel=$(ls -t resultados/aceite-inf-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

I1_COMMAND_TOPIC=${I1_COMMAND_TOPIC:-ods.i1.command}

case "${1:-subir}" in
  i1)     shift; checar_kafka; pedir_i1 "$@" ;;
  i3)     rodar i3 i3 ;;
  # I4 fora: i4)     rodar i4 i4-video ;;
  i4)     erro "o I4 está fora da build inf (27/11/2026); veja o docker-compose.yml" ;;
  # I5 fora: i5)     rodar i5 i5-audio; echo "Transcrição em ods.i5.transcript em alguns segundos: ./inf.sh log i5" ;;
  i5)     erro "o I5 está fora da build inf (24/11/2026); veja o docker-compose.yml" ;;
  i6|i7|i8)
          erro "o $1 é o contínuo da build $(case $1 in i6) echo inf_a2 ;; i7) echo inf_a8 ;; *) echo inf_a1 ;; esac) desde 27/11/2026 (../inf_aX/inf_aX.sh status | log | testar)" ;;
  contar) contar ;;
  log)    shift; dc logs -f --tail 50 "${1:?uso: ./inf.sh log <serviço>}" ;;
  *)      ods_principal "$@" ;;
esac
