#!/usr/bin/env bash
# inf.sh — build "inf": todas as inferências (I1–I9) numa build só (P3 / SIS-1).
#
#   ./inf.sh               o mesmo que ./inf.sh subir
#   ./inf.sh subir         confere a placa e o I1, baixa o código, constrói o que falta (em etapas,
#                          com limpeza) e sobe os contínuos: i2, i4-server, i4, i5, i6, i9
#   ./inf.sh subir --reconstruir   reconstrói todas as imagens
#   ./inf.sh i1 [EQUIPE] [QUADROS] pede detecções ao I1 (builds/i1) por ods.i1.command
#                          (padrão: INF_I1_EQUIPE e INF_I1_QUADROS do inf.env; equipes do I1:
#                          VER5 placas, VER3/VER6 EPI, VER1 indústria, INV1 esporte)
#   ./inf.sh i3            calibração da quadra do A4 → ods.i3.calibration + ods.artifact.published
#   ./inf.sh i4            manda I4_VIDEO ao servidor do I4 (como a webcam) → ods.i4.*
#   ./inf.sh i5            manda I5_AUDIO como se fosse o P5 → o i5 transcreve em ods.i5.transcript
#   ./inf.sh i7            lê placas de VIDEO_DIR/I7_VIDEO → ods.i7.plate_read
#   ./inf.sh i8            publica os 4 eventos de exemplo do I8 → ods.industria.defeito_classificado
#   ./inf.sh contar        mensagens por tópico das inferências
#   ./inf.sh testar        dispara todas e confere cada tópico → resultados/aceite-inf-*.txt
#   ./inf.sh log <serviço> acompanha o log de um serviço (Ctrl+C para sair)
#   ./inf.sh status        containers, I1, memória, disco e Kafka
#   ./inf.sh parar         derruba a build (o I1 continua de pé: é de builds/i1)
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=inf
SEGREDOS=()
# Menores primeiro, as maiores (torch) por último e sozinhas: o disco da Jetson é pequeno.
ETAPAS=("i2 i3 i6 i9 i4-video" "i8" "i4-server" "i4" "i5" "i7")
ONESHOT=(kafka-topicos)

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

TOPICOS_RE='^(ods\.i[0-9]\..*|ods\.p5\.audio_chunk|ods\.artifact\.published|ods\.industria\.defeito_classificado)$'

# ---------------------------------------------------------------- I1 (outra build)

container_i1() {
  docker ps -aq --filter label=com.docker.compose.project=ods-i1 \
    --filter label=com.docker.compose.service=i1 | head -1
}

# O I1 é o de builds/i1. Esta build só funciona com ele de pé e no MESMO broker.
checar_i1() {
  local c estado broker_i1
  c=$(container_i1)
  if [[ -z "$c" ]]; then
    aviso "o I1 (builds/i1) não está nesta placa: I2 e I9 sobem, mas ficam sem detecções.
  Para subir: ../i1/i1.sh"
    return 0
  fi
  estado=$(docker inspect -f '{{.State.Status}}' "$c")
  [[ "$estado" == running ]] || aviso "o I1 (builds/i1) está $estado. Para subir: ../i1/i1.sh"
  broker_i1=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | sed -n 's/^ODS_KAFKA_BROKER=//p')
  if [[ -n "$broker_i1" && "$broker_i1" != "$KAFKA_BROKER" ]]; then
    erro "o I1 usa o Kafka $broker_i1 e esta build, $KAFKA_BROKER: os pedidos não chegariam.
  Use o mesmo broker nas duas (inf.local.env aqui, ou i1.local.env em ../i1)."
  fi
  ok "I1 (builds/i1) $estado, no mesmo Kafka ($KAFKA_BROKER)"
}

# ---------------------------------------------------------------- conferências

checar_entradas() {
  checar_i1
  [[ -d "$VIDEO_DIR" ]] || erro "falta a pasta $VIDEO_DIR (a do I1). Rode antes: ../i1/i1.sh videos"
  [[ -w "$VIDEO_DIR" ]] || aviso "sem escrita em $VIDEO_DIR: o vídeo de QR do I6 não poderá ser gerado.
  Uma vez só: sudo chown $(id -un) $VIDEO_DIR"
  entrada_arquivo "$VIDEO_DIR/$I7_VIDEO" "vídeo do I7" "o ./inf.sh i7 não terá o que ler"
  # I4_VIDEO e I5_AUDIO_DIR ficam nos clones: no primeiro "subir" ainda não existem.
  [[ -d "$SRC_DIR/i4" ]] && entrada_arquivo "$I4_VIDEO" "vídeo do I4" "o ./inf.sh i4 não terá o que mandar"
  [[ -d "$SRC_DIR/i5" ]] && entrada_arquivo "$I5_AUDIO_DIR/$I5_AUDIO" "áudio do I5" "o ./inf.sh i5 não terá o que mandar"
  livre_ram_mb >/dev/null
  return 0
}

livre_ram_mb() {
  local mb; mb=$(awk '/^MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  echo "$mb"
  # Com o I1 (TensorRT), o Kafka e os contínuos daqui, a placa de 7,4 GB fica no limite.
  (( mb >= 1500 )) || aviso "só ${mb} MB de memória disponível: o TensorRT do I1 pode falhar (OUT_OF_MEMORY)" >&2
}

# ---------------------------------------------------------------- depois do "up"

gerar_video_qr() {
  [[ "$I6_VIDEO" == inf-qr.mp4 ]] || return 0
  [[ -f "$VIDEO_DIR/inf-qr.mp4" ]] && return 0
  dc --profile i6 run --rm -T i6-gerar-video || aviso "não gerei $VIDEO_DIR/inf-qr.mp4: o I6 fica sem vídeo"
}

pos_subida() {
  etapa "Entradas"
  gerar_video_qr
  entrada_arquivo "$VIDEO_DIR/$I6_VIDEO" "vídeo do I6 (relido em laço)" "o I6 fica tentando abrir"
  echo
  echo "Contínuos de pé. Para disparar cada inferência: ./inf.sh i1 | i3 | i4 | i5 | i7 | i8"
  echo "Tudo de uma vez, conferindo os tópicos: ./inf.sh testar"
  echo "Webcam no I4: python webcam.py --url ws://<placa>:18080/ws/video (I4_SERVER_BIND=$I4_SERVER_BIND)"
}

# ---------------------------------------------------------------- disparos

kafka() { docker run --rm -i "$KAFKA_IMG" "$@"; }

pedir_i1() {
  local equipe=${1:-$INF_I1_EQUIPE} quadros=${2:-$INF_I1_QUADROS} sid=${3:-}
  [[ "$quadros" =~ ^[0-9]+$ ]] || erro "QUADROS deve ser um número (recebi '$quadros')"
  sid=${sid:-inf-$equipe-$(date +%H%M%S)}
  local json="{\"action\": \"START\", \"squad\": \"$equipe\", \"source_id\": \"$sid\", \"max_frames\": $quadros}"
  [[ -n "$(container_i1)" ]] || aviso "o I1 (builds/i1) não está nesta placa: o pedido fica no tópico até ele subir"
  echo "$json" | kafka kafka-console-producer --bootstrap-server "$KAFKA_BROKER" --topic "$I1_COMMAND_TOPIC" 2>/dev/null \
    || erro "não consegui publicar em $I1_COMMAND_TOPIC ($KAFKA_BROKER)"
  ok "pedido ao I1: $json"
  local c; c=$(container_i1)
  echo "  acompanhe: docker logs -f --tail 20 ${c:-<container do i1>}"
}

rodar() {   # rodar <perfil> <serviço>
  dc --profile "$1" run --rm -T "$2"
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

esperar_topico() {   # esperar_topico <tópico> <segundos>: até chegar mensagem nova
  local limite=$((SECONDS + $2))
  while (( SECONDS < limite )); do
    offsets > "$DEPOIS"
    (( $(delta "$1") > 0 )) && return 0
    sleep 10
  done
  return 1
}

testar() {
  etapa "Conferindo"
  aceite_conferir i2 i4-server i4 i5 i6 i9
  checar_i1
  local c1; c1=$(container_i1)
  [[ -n "$c1" && "$(docker inspect -f '{{.State.Status}}' "$c1")" == running ]] \
    || erro "o I1 (builds/i1) não está rodando; suba com ../i1/i1.sh antes do teste"
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
  local cod_i3=0 cod_i8=0 cod_i5=0 cod_i4=0 cod_i7=0
  echo "-- I3";  rodar i3 i3  || cod_i3=$?
  echo "-- I8";  rodar i8 i8  || cod_i8=$?
  echo "-- I5 (áudio como P5)"; rodar i5 i5-audio || cod_i5=$?
  echo "-- I4 (vídeo como webcam)"; rodar i4 i4-video || cod_i4=$?
  echo "-- I7 (placas no vídeo)"; rodar i7 i7 || cod_i7=$?

  etapa "Esperando o I1/I9 e o processamento do I5 e do I4"
  esperar_topico ods.i9.ppe_compliance 180 || true
  sleep 30
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
  else registrar T-I2 FALHOU "I2 trilhas" "nenhuma (dc logs i2)"; fi
  d=$(delta ods.artifact.published)
  if (( cod_i3 == 0 && d > 0 )); then registrar T-I3 PASSOU "I3 calibração anunciada" "artifact.published +$d, calibration +$(delta ods.i3.calibration)"
  else registrar T-I3 FALHOU "I3 calibração anunciada" "código $cod_i3, artifact.published +$d"; fi
  d=$(delta ods.i4.sign)
  if (( cod_i4 != 0 )); then registrar T-I4 FALHOU "I4 sinais" "envio do vídeo terminou com código $cod_i4"
  elif (( d > 0 )); then registrar T-I4 PASSOU "I4 sinais" "sign +$d, keypoints +$(delta ods.i4.keypoints), facial_marker +$(delta ods.i4.facial_marker)"
  elif (( $(delta ods.i4.keypoints) > 0 )); then registrar T-I4 AVISO "I4 sinais" "sem sinal reconhecido; keypoints +$(delta ods.i4.keypoints)"
  else registrar T-I4 FALHOU "I4 sinais" "nada publicado (dc logs i4 i4-server)"; fi
  d=$(delta ods.i5.transcript)
  if (( cod_i5 != 0 )); then registrar T-I5 FALHOU "I5 transcrição" "envio do áudio terminou com código $cod_i5"
  elif (( d > 0 )); then registrar T-I5 PASSOU "I5 transcrição" "$d mensagens (audio_chunk +$(delta ods.p5.audio_chunk))"
  elif [[ "$I5_MODO" == wake-word ]]; then registrar T-I5 AVISO "I5 transcrição" "nenhuma; modo wake-word: o áudio diz \"lexie\"?"
  else registrar T-I5 FALHOU "I5 transcrição" "nenhuma (dc logs i5)"; fi
  d=$(delta ods.i6.code_read)
  if (( d > 0 )); then registrar T-I6 PASSOU "I6 QR" "$d leituras de $I6_VIDEO"
  else registrar T-I6 FALHOU "I6 QR" "nenhuma leitura (dc logs i6)"; fi
  d=$(delta ods.i7.plate_read)
  if (( cod_i7 != 0 )); then registrar T-I7 FALHOU "I7 placas" "terminou com código $cod_i7"
  elif (( d > 0 )); then registrar T-I7 PASSOU "I7 placas" "$d leituras em $I7_QUADROS quadros de $I7_VIDEO"
  else registrar T-I7 AVISO "I7 placas" "rodou, sem leitura com confiança >= 0,9 em $I7_QUADROS quadros"; fi
  d=$(delta ods.industria.defeito_classificado)
  if (( cod_i8 == 0 && d >= 4 )); then registrar T-I8 PASSOU "I8 eventos de exemplo" "+$d"
  else registrar T-I8 FALHOU "I8 eventos de exemplo" "código $cod_i8, +$d (esperado 4)"; fi
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
    echo "I1 (builds/i1): $(docker inspect -f '{{.State.Status}}, {{.RestartCount}} reinícios' "$c1")"
  else
    echo "I1 (builds/i1): ausente (../i1/i1.sh)"
  fi
  local ids
  mapfile -t ids < <(docker ps -q --filter label=com.docker.compose.project=ods-inf; [[ -n "$c1" ]] && echo "$c1")
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
  i4)     rodar i4 i4-video ;;
  i5)     rodar i5 i5-audio; echo "Transcrição em ods.i5.transcript em alguns segundos: ./inf.sh log i5" ;;
  i7)     rodar i7 i7 ;;
  i8)     rodar i8 i8 ;;
  contar) contar ;;
  log)    shift; dc logs -f --tail 50 "${1:?uso: ./inf.sh log <serviço>}" ;;
  *)      ods_principal "$@" ;;
esac
