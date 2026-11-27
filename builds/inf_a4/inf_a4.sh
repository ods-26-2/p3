#!/usr/bin/env bash
# inf_a4.sh — build "inf_a4": só as inferências I1, I2 e I3, no Kafka da nuvem (P3 / SIS-1).
#
#   ./inf_a4.sh              o mesmo que ./inf_a4.sh subir
#   ./inf_a4.sh subir        confere a placa, baixa o código, constrói o que falta (a imagem do
#                                  I1 é a mesma do builds/i1), sobe i1 + i2 e prepara as engines
#   ./inf_a4.sh subir --reconstruir   reconstrói as imagens
#   ./inf_a4.sh i1 [EQUIPE] [QUADROS] pede detecções ao I1 desta build (ods.i1.command)
#                                  (padrão: INF_I1_EQUIPE e INF_I1_QUADROS do .env; equipes do I1:
#                                  VER5 placas, VER3/VER6 EPI, VER1 indústria, INV1 esporte)
#   ./inf_a4.sh comando '<json>'  manda um comando qualquer em ods.i1.command
#   ./inf_a4.sh i3           calibração da quadra do A4 → ods.i3.calibration + ods.artifact.published
#   ./inf_a4.sh contar       mensagens por tópico da build
#   ./inf_a4.sh p4 [VIDEO] [QUADROS]   P4 da SIS-2 → I1: toca VIDEO (padrão P4_VIDEO) pelo P4 nativo
#                                  da placa (sudo -u P4_USUARIO), lê um quadro com o leitor do P4,
#                                  pede ao I1 "source": "video" e confere as detecções no Kafka
#                                  → resultados/p4-i1-*.txt. Na 1ª vez pergunta se liga o contorno
#                                  I1_P4_DIR=/tmp no inf_a4.local.env (--preparar: sem perguntar)
#   ./inf_a4.sh p4 --desfazer      tira o contorno e recria o i1 com a pasta de sempre
#   ./inf_a4.sh testar       cadeia I1 → I2 e I3 pelo Kafka + contrato de cada mensagem com o
#                                  schema do próprio repositório → resultados/aceite-inf_a4-*.txt
#   ./inf_a4.sh repos [i1 i2 i3]  suítes de teste dos repositórios nas imagens desta build
#                                  (validacao/inf/testar-inf-repos.sh --build inf_a4)
#   ./inf_a4.sh engines      só confere/compila as engines TensorRT do I1
#   ./inf_a4.sh log <serviço> acompanha o log de um serviço (Ctrl+C para sair)
#   ./inf_a4.sh status       containers, I1, memória, disco e Kafka
#   ./inf_a4.sh parar        derruba a build (volumes mantidos)
#
# Kafka: o da nuvem (KAFKA_BROKER do .env; o da placa só por inf_a4.local.env). O container
# "kafka" da placa tem de continuar rodando: a build confere e avisa, e nunca o para.
# O I1 é próprio desta build: se o I1 permanente (builds/i1) estiver no MESMO broker, a subida
# recusa (dois orquestradores disputariam a GPU e os pedidos).
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Guardar no notebook e subir de lá sem reconstruir (rodam NO NOTEBOOK): ./guardar-no-notebook.sh e
# ./subir-do-notebook.sh [pasta]
# Guia: validacao/inf_a4/GUIA-BUILD-INF-A4.md
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=inf_a4
SEGREDOS=()
# A do I1 (base TensorRT, a maior) por último e sozinha; se já existe (builds/i1), é pulada.
ETAPAS=("i2 i3" "i1")
ONESHOT=(kafka-topicos)

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

TOPICOS_RE='^(ods\.i1\.command|ods\.i1\.detections|ods\.i2\.tracks|ods\.i3\.calibration|ods\.artifact\.published)$'
I1_COMMAND_TOPIC=${I1_COMMAND_TOPIC:-ods.i1.command}
# Mensagens lidas por tópico para conferir o contrato
MAX_CONTRATO=${MAX_CONTRATO:-500}

# ---------------------------------------------------------------- conferências

checar_gpu() {
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' \
    || erro "o Docker desta placa não tem o runtime nvidia; o I1 (TensorRT) não sobe sem ele.
  Confira com: docker info | grep -i runtime"
  ok "Docker com runtime nvidia (GPU para o I1)"
}

# Pastas do host montadas no I1. Criadas aqui: se faltarem, o Docker as cria como root.
checar_pasta() {   # checar_pasta <pasta> <para quê>
  [[ -d "$1" ]] && return 0
  if mkdir -p "$1" 2>/dev/null; then ok "pasta criada: $1 ($2)"
  else erro "não consegui criar $1 ($2). Uma vez só: sudo mkdir -p $1 && sudo chown $(id -un) $1"; fi
}

# O I1 permanente (builds/i1), se existir nesta placa
container_i1_permanente() {
  docker ps -q --filter label=com.docker.compose.project=ods-i1 \
    --filter label=com.docker.compose.service=i1 | head -1
}

# Dois orquestradores no mesmo broker: os dois carregariam modelo na GPU (7,4 GB divididos com a
# CPU) e, com grupos diferentes, os dois atenderiam o mesmo pedido. Em brokers diferentes, só avisa.
checar_i1_permanente() {
  local c broker
  c=$(container_i1_permanente)
  [[ -n "$c" ]] || { ok "I1 permanente (builds/i1) parado ou ausente: o I1 desta build fica sozinho na GPU"; return 0; }
  broker=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | sed -n 's/^ODS_KAFKA_BROKER=//p')
  if [[ "$broker" == "$KAFKA_BROKER" ]]; then
    erro "o I1 permanente (builds/i1) está de pé no MESMO Kafka ($KAFKA_BROKER).
  Dois orquestradores atenderiam os mesmos pedidos e disputariam a GPU. Pare-o enquanto usa esta
  build: ../i1/i1.sh parar  (para voltar: ./inf_a4.sh parar && ../i1/i1.sh)"
  fi
  aviso "o I1 permanente (builds/i1) também está de pé (Kafka $broker). Cada um atende o seu broker,
  mas os dois dividem a GPU: pedidos simultâneos podem faltar memória (OUT_OF_MEMORY)."
}

# O Kafka da turma NA PLACA tem de continuar rodando (usuário, 25/11/2026), mesmo quando esta build
# usa o da nuvem. Só confere e avisa: o container é de outro grupo (nunca parar nem recriar).
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
  checar_gpu
  checar_i1_permanente
  checar_pasta "$I1_ENGINES_DIR" "engines TensorRT"
  checar_pasta "$I1_P4_DIR" "sockets do P4 de outra build"
  # Vídeos do P3 (/videos-p3 no container): o mesmo instalador do builds/i1 (assets/ → VIDEO_DIR)
  etapa "Vídeos do P3 (../i1/i1.sh videos), em /videos-p3 no I1"
  "$ODS_DIR_BUILDS/i1/i1.sh" videos || aviso "não instalei os vídeos do P3 (/videos-p3)"
  etapa "Pasta original dos vídeos do I1 (SIS-2): $I1_VIDEOS_ORIGINAL"
  videos_originais
  livre_ram_mb >/dev/null
  return 0
}

# A pasta da SIS-2 (usuário sys2) pode não ser legível pelo usuário ods; o Docker (root) a monta.
# Lista pelo próprio Docker, só leitura, na imagem do Kafka que já está na placa.
listar_originais() {
  # --mount (e não -v): se a pasta não existir, falha em vez de criá-la como root
  docker run --rm --network none --mount "type=bind,source=$I1_VIDEOS_ORIGINAL,target=/v,readonly" \
    --entrypoint ls "$KAFKA_IMG" -1 /v 2>/dev/null
}
videos_originais() {
  local lista
  lista=$(listar_originais) || true
  if [[ -z "$lista" ]]; then
    aviso "pasta $I1_VIDEOS_ORIGINAL vazia ou ausente: pedido sem \"source\" falha (use \"source\": \"/videos-p3/<SQUAD>.mp4\")"
    return 0
  fi
  ok "vídeos na pasta original: $(tr '\n' ' ' <<<"$lista")"
  grep -qx "$INF_I1_EQUIPE.mp4" <<<"$lista" \
    || aviso "falta $INF_I1_EQUIPE.mp4 na pasta original: o ./inf_a4.sh testar não terá o que ler"
  return 0
}

livre_ram_mb() {
  local mb; mb=$(awk '/^MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  echo "$mb"
  (( mb >= 1500 )) || aviso "só ${mb} MB de memória disponível: o TensorRT do I1 pode falhar (OUT_OF_MEMORY)" >&2
}

# A Jetson divide a RAM entre CPU e GPU; esvaziar o cache de páginas não apaga dados (como no builds/i1).
liberar_memoria() {
  local antes depois cmd='sync; echo 3 > /proc/sys/vm/drop_caches'
  antes=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
  if { [[ -t 0 ]] && sudo sh -c "$cmd"; } || sudo -n sh -c "$cmd" 2>/dev/null; then
    depois=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
    ok "memória livre para a GPU: ${antes} MB → ${depois} MB (cache de páginas esvaziado)"
  else
    aviso "memória livre: ${antes} MB. Sem sudo para esvaziar o cache; o TensorRT pode faltar memória.
  À mão: sudo sh -c '$cmd'"
  fi
}

engine_existe() { [[ -d "$I1_ENGINES_DIR/${1/\//-}" ]]; }

preparar_engines() {
  etapa "Engines TensorRT do I1 ($I1_PACOTES) em $I1_ENGINES_DIR"
  local p faltam=()
  for p in $I1_PACOTES; do engine_existe "$p" || faltam+=("$p"); done
  if (( ${#faltam[@]} )); then
    echo "  a compilar: ${faltam[*]} (~7 min cada na primeira vez)"
    liberar_memoria
  fi
  dc --profile engine run --rm -T i1-engine < /dev/null || erro "as engines do I1 não ficaram prontas; veja a saída acima"
  checar_disco
}

# ---------------------------------------------------------------- depois do "up"

container_i1() { dc ps -aq i1 2>/dev/null | head -1; }

esperar_i1_pronto() {
  local limite=$((SECONDS + 60)) c
  c=$(container_i1)
  until docker logs "$c" 2>&1 | grep -q 'Aguardando comandos'; do
    (( SECONDS < limite )) || { docker logs --tail 30 "$c" 2>&1; erro "o orquestrador não ficou pronto em 1 minuto"; }
    sleep 2
  done
  ok "I1 pronto: $(docker logs "$c" 2>&1 | grep 'Aguardando comandos' | tail -1)"
}

pos_subida() {
  preparar_engines
  etapa "Orquestrador do I1"
  esperar_i1_pronto
  echo
  echo "Pedido ao I1:   ./inf_a4.sh i1 [EQUIPE] [QUADROS]   (ex.: ./inf_a4.sh i1 INV1 150)"
  echo "Calibração I3:  ./inf_a4.sh i3"
  echo "Testes:         ./inf_a4.sh testar   ·   ./inf_a4.sh repos"
}

# ---------------------------------------------------------------- disparos

kafka() { docker run --rm -i "$KAFKA_IMG" "$@"; }

publicar_comando() {   # publicar_comando <json>
  echo "$1" | kafka kafka-console-producer --bootstrap-server "$KAFKA_BROKER" --topic "$I1_COMMAND_TOPIC" 2>/dev/null \
    || erro "não consegui publicar em $I1_COMMAND_TOPIC ($KAFKA_BROKER)"
  ok "comando em $I1_COMMAND_TOPIC: $1"
}

pedir_i1() {   # pedir_i1 [EQUIPE] [QUADROS] [source_id]
  local equipe=${1:-$INF_I1_EQUIPE} quadros=${2:-$INF_I1_QUADROS} sid=${3:-}
  [[ "$quadros" =~ ^[0-9]+$ ]] || erro "QUADROS deve ser um número (recebi '$quadros')"
  sid=${sid:-inf-a4-$equipe-$(date +%H%M%S)}
  [[ -n "$(container_i1)" ]] || aviso "o I1 desta build não está de pé: o pedido fica no tópico (o I1 lê só pedidos novos)"
  publicar_comando "{\"action\": \"START\", \"squad\": \"$equipe\", \"source_id\": \"$sid\", \"max_frames\": $quadros}"
  echo "  acompanhe: ./inf_a4.sh log i1"
}

# Entrada vazia (< /dev/null): com -T a entrada deixa de ser terminal, e o I3 (--linhas) lê um csv
# opcional do stdin até o fim; sem o /dev/null ele esperava o teclado para sempre (Jetson, 25/11).
rodar() {   # rodar <perfil> <serviço>
  dc --profile "$1" run --rm -T "$2" < /dev/null
}

# ---------------------------------------------------------------- contagem por tópico

# "tópico:partição:offset", uma linha por partição (uma chamada ao broker)
offsets_brutos() {
  kafka kafka-get-offsets --bootstrap-server "$KAFKA_BROKER" --topic "$TOPICOS_RE" 2>/dev/null \
    | awk -F: 'NF >= 3' | sort
}
# "tópico total" (soma das partições)
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
registrar() { RES+=("$1|$2|$3|$4"); }   # registrar <id> <resultado> <o quê> <detalhe>

delta() {   # delta <tópico>: mensagens novas (todas as origens) entre as duas contagens
  local a d
  a=$(somar "$ANTES" | awk -v t="$1" '$1 == t { print $2 }')
  d=$(somar "$DEPOIS" | awk -v t="$1" '$1 == t { print $2 }')
  echo $(( ${d:-0} - ${a:-0} ))
}

# Lê as mensagens novas de um tópico (de cada partição, a partir do offset de ANTES) para um arquivo
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
  # Tópico que não existia antes do teste: lê do começo
  if ! grep -q "^$topico:" "$ANTES"; then
    kafka kafka-console-consumer --bootstrap-server "$KAFKA_BROKER" --topic "$topico" --from-beginning \
      --max-messages "$MAX_CONTRATO" --timeout-ms 20000 >> "$arq" 2>/dev/null || true
  fi
}

# Valida um arquivo de mensagens com o schema do repositório produtor, dentro da imagem dele.
# Saída: "válidas total primeiro-erro" e, na linha seguinte, as artifact_version vistas.
contrato() {   # contrato <imagem> <python> <schema na imagem> <arquivo> [source_id]
  local saida
  # O validador sai com 1 quando há mensagem inválida: o resumo vale do mesmo jeito.
  saida=$(docker run --rm --network none --entrypoint "$2" \
    -v "$ODS_DIR_APP/contrato:/p3/contrato:ro" -v "$(readlink -f "$4"):/p3/msgs.jsonl:ro" \
    "$1" -u /p3/contrato/validar.py "$3" /p3/msgs.jsonl "${5:--}" 2>&1) || true
  grep -E '^(CONTRATO|VERSOES) ' <<<"$saida" \
    || echo "CONTRATO 0 0 a validação não rodou na imagem $1: $(tail -1 <<<"$saida" | cut -c1-160)"
}

# Item de contrato a partir da saída de contrato()
avaliar_contrato() {   # avaliar_contrato <id> <o quê> <saída>
  local v t e
  read -r _ v t e <<<"$(grep '^CONTRATO' <<<"$3")"
  if (( ${t:-0} == 0 )); then registrar "$1" FALHOU "$2" "nenhuma mensagem para conferir ($e)"
  elif (( v == t )); then registrar "$1" PASSOU "$2" "$v de $t válidas"
  else registrar "$1" FALHOU "$2" "$v de $t válidas; 1º erro: $e"; fi
}

esperar_sessao() {   # esperar_sessao <container> <equipe> <desde> <segundos>
  local limite=$((SECONDS + $4))
  while (( SECONDS < limite )); do
    docker logs --since "$3" "$1" 2>&1 | grep -q "Sessão '$2' encerrada" && return 0
    sleep 5
  done
  return 1
}

testar() {
  etapa "Conferindo"
  aceite_conferir i1 i2
  checar_kafka_local
  checar_i1_permanente
  local c1 p; c1=$(container_i1)
  for p in $I1_PACOTES; do engine_existe "$p" || erro "falta a engine de $p; rode ./inf_a4.sh engines antes"; done
  ok "engines de todos os pacotes presentes"
  liberar_memoria
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  local rel="resultados/aceite-inf_a4-$ts.txt" pasta="resultados/aceite-inf_a4-$ts"
  mkdir -p "$pasta"
  ANTES="$pasta/offsets-antes.txt"; DEPOIS="$pasta/offsets-depois.txt"
  local ram_antes restarts_antes t0 sid="inf-a4-teste-$ts"
  ram_antes=$(livre_ram_mb)
  restarts_antes=$(docker inspect -f '{{.RestartCount}}' "$c1")
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  offsets_brutos > "$ANTES"
  [[ -s "$ANTES" ]] || erro "não consegui contar as mensagens em $KAFKA_BROKER"

  etapa "Disparos"
  pedir_i1 "$INF_I1_EQUIPE" "$INF_I1_QUADROS" "$sid"
  local cod_i3=0
  echo "-- I3 (calibração da quadra)"; rodar i3 i3 || cod_i3=$?

  etapa "Esperando o I1 terminar a sessão ($INF_I1_EQUIPE, $INF_I1_QUADROS quadros) e o I2 rastrear"
  local sessao=1
  esperar_sessao "$c1" "$INF_I1_EQUIPE" "$t0" 300 || sessao=0
  sleep 15
  offsets_brutos > "$DEPOIS"
  local ram_depois restarts_depois oom
  ram_depois=$(livre_ram_mb)
  restarts_depois=$(docker inspect -f '{{.RestartCount}}' "$c1")
  docker logs --since "$t0" "$c1" > "$pasta/i1.log" 2>&1 || true
  oom=$(grep -c 'OUT_OF_MEMORY' "$pasta/i1.log" || true)

  etapa "Lendo as mensagens novas e conferindo o contrato"
  ler_novas ods.i1.detections "$pasta/i1.detections.jsonl"
  ler_novas ods.i2.tracks "$pasta/i2.tracks.jsonl"
  ler_novas ods.i3.calibration "$pasta/i3.calibration.jsonl"
  ler_novas ods.artifact.published "$pasta/artifact.published.jsonl"
  local img_i1 img_i2 img_i3
  img_i1="ods-i1-gpu:$I1_REF"; img_i2="ods-i2:$I2_REF"; img_i3="ods-i3:$I3_REF"
  local c_i1 c_i2 c_cal c_art
  c_i1=$(contrato "$img_i1" python3 /app/schemas/ods.i1.detections.v1.0.schema.json "$pasta/i1.detections.jsonl" "$sid")
  c_i2=$(contrato "$img_i2" python /app/schemas/ods.i2.tracks.v1.0.schema.json "$pasta/i2.tracks.jsonl" "$sid")
  c_cal=$(contrato "$img_i3" python /app/schemas/ods.i3.calibration.v1.0.schema.json "$pasta/i3.calibration.jsonl" inf-a4-quadra)
  c_art=$(contrato "$img_i3" python /app/schemas/ods.artifact.published.v1.0.schema.json "$pasta/artifact.published.jsonl")

  # --- avaliação
  local n_i1 n_i2 versoes
  read -r _ _ n_i1 _ <<<"$(grep '^CONTRATO' <<<"$c_i1")"
  read -r _ _ n_i2 _ <<<"$(grep '^CONTRATO' <<<"$c_i2")"
  versoes=$(sed -n 's/^VERSOES //p' <<<"$c_i1")
  if (( ${n_i1:-0} > 0 )); then registrar T-I1 PASSOU "I1 detecções ($INF_I1_EQUIPE)" "$n_i1 mensagens do $sid"
  else registrar T-I1 FALHOU "I1 detecções ($INF_I1_EQUIPE)" "nenhuma do $sid; veja $pasta/i1.log"; fi
  if (( sessao )); then registrar T-I1S PASSOU "I1 encerrou a sessão" "$(grep "Sessão '$INF_I1_EQUIPE' encerrada" "$pasta/i1.log" | tail -1 | sed 's/.*encerrada/encerrada/')"
  else registrar T-I1S FALHOU "I1 encerrou a sessão" "sem 'Sessão $INF_I1_EQUIPE encerrada' em 5 min ($pasta/i1.log)"; fi
  if [[ -n "$versoes" && "$versoes" != *,* && "$versoes" == *-fp16 ]]; then registrar T-I1G PASSOU "I1 na GPU (TensorRT)" "artifact_version $versoes"
  else registrar T-I1G FALHOU "I1 na GPU (TensorRT)" "artifact_version '${versoes:-?}' (esperado …-fp16)"; fi
  if (( restarts_depois == restarts_antes && oom == 0 )); then registrar T-I1M PASSOU "I1 sem reinício nem OUT_OF_MEMORY" "RestartCount $restarts_antes"
  else registrar T-I1M FALHOU "I1 sem reinício nem OUT_OF_MEMORY" "RestartCount $restarts_antes → $restarts_depois; OUT_OF_MEMORY: $oom"; fi
  if (( ${n_i2:-0} > 0 )); then registrar T-I2 PASSOU "I2 trilhas do $sid" "$n_i2 mensagens"
  else registrar T-I2 FALHOU "I2 trilhas do $sid" "nenhuma (./inf_a4.sh log i2)"; fi
  local d_art d_cal
  d_art=$(delta ods.artifact.published); d_cal=$(delta ods.i3.calibration)
  if (( cod_i3 == 0 && d_art > 0 )); then registrar T-I3 PASSOU "I3 calibração anunciada" "artifact.published +$d_art, calibration +$d_cal"
  else registrar T-I3 FALHOU "I3 calibração anunciada" "código $cod_i3, artifact.published +$d_art, calibration +$d_cal"; fi
  avaliar_contrato T-C1 "contrato ods.i1.detections (schema do I1)" "$c_i1"
  avaliar_contrato T-C2 "contrato ods.i2.tracks (schema do I2)" "$c_i2"
  avaliar_contrato T-C3 "contrato ods.i3.calibration (schema do I3)" "$c_cal"
  avaliar_contrato T-C4 "contrato ods.artifact.published (I3)" "$c_art"

  # --- relatório
  local pa=0 f=0 a=0 linha
  for linha in "${RES[@]}"; do
    case "$(cut -d'|' -f2 <<<"$linha")" in PASSOU) pa=$((pa+1)) ;; FALHOU) f=$((f+1)) ;; *) a=$((a+1)) ;; esac
  done
  {
    echo "Teste de aceitação da build inf_a4 — $(date '+%Y-%m-%d %H:%M:%S') — $(uname -n)"
    echo "Kafka: $KAFKA_BROKER · I1 $INF_I1_EQUIPE, $INF_I1_QUADROS quadros, source_id $sid · memória disponível: $ram_antes MB → $ram_depois MB"
    echo "Commits: I1 ${I1_REF:0:7} · I2 ${I2_REF:0:7} · I3 ${I3_REF:0:7}"
    echo
    for linha in "${RES[@]}"; do
      IFS='|' read -r id r oque det <<<"$linha"
      printf '%-6s %-7s %-42s %s\n' "$id" "$r" "$oque" "$det"
    done
    echo
    echo "Mensagens por tópico, todas as origens (antes → depois):"
    join -a1 -a2 -e 0 -o 0,1.2,2.2 <(somar "$ANTES") <(somar "$DEPOIS") | awk '{ printf "  %-28s %8s → %8s\n", $1, $2, $3 }'
    echo
    echo "Resumo: PASSOU $pa, FALHOU $f, AVISO $a"
  } | tee "$rel"
  echo
  echo "Relatório: $ODS_DIR_APP/$rel (mensagens e log do I1 em $pasta/)"
  (( f == 0 ))
}

# ---------------------------------------------------------------- P4 da SIS-2 → I1 (./inf_a4.sh p4)
#
# O P4 roda nativo na placa (pasta, venv e usuário da SIS-2), chamado com sudo -u $P4_USUARIO. O
# socket do modo arquivo é fixo no código do P4 (/tmp/p4_file_shm, no /tmp da PLACA), e o I1 desta
# build vê como /tmp a pasta I1_P4_DIR. Para o I1 achar o socket, I1_P4_DIR=/tmp no inf_a4.local.env
# (fora do Git): CONTORNO PROVISÓRIO, desfeito com ./inf_a4.sh p4 --desfazer. A memória
# compartilhada em si vem pelo ipc: host.
#
# NADA do P4 nem das pastas do sys2 é alterado (regra do usuário, 26/11/2026): como sys2 só se lê
# (test, git log, git --no-optional-locks status, que não regrava o índice) e se rodam os scripts do
# próprio P4 com PYTHONDONTWRITEBYTECODE=1 (sem __pycache__ na pasta dele). O que o P4 grava fica no
# /tmp da placa: o socket e a trava (/tmp/p4_file_shm, /tmp/p4_demo_file.lock) e o PNG do leitor
# (/tmp/p4_frame_recebido.png). Socket velho de outra execução não é apagado: o comando para e avisa.

# Fixos no código do P4 (src/main.py e scripts/p4_demo.sh); a variável só serve à simulação
P4_SOCKET=${P4_SOCKET:-/tmp/p4_file_shm}
P4_LOCK=${P4_LOCK:-/tmp/p4_demo_file.lock}
P4_MARCA='# ./inf_a4.sh p4: o I1 vê o /tmp da placa (socket do P4 da SIS-2). Desfazer: ./inf_a4.sh p4 --desfazer'
P4_PID=""

como_p4() { sudo -u "${P4_USUARIO:?defina P4_USUARIO}" "$@"; }

# Processo vivo? (o P4 roda sob o sudo, que é do root: "kill -0" dá EPERM e pareceria morto)
vivo() { [[ -r "/proc/$1/stat" ]] && [[ "$(awk '{ print $3 }' "/proc/$1/stat" 2>/dev/null)" != Z ]]; }

i1_ve_tmp_da_placa() {
  local c; c=$(container_i1)
  [[ -n "$c" ]] || return 1
  [[ "$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/tmp"}}{{.Source}}{{end}}{{end}}' "$c")" == /tmp ]]
}

# Recria só o i1 com o I1_P4_DIR atual (o compose usa a variável exportada pela lib)
recriar_i1() {
  ODS_LOCAL_ENV=()
  [[ -f "$APP.local.env" ]] && ODS_LOCAL_ENV=(--env-file "$APP.local.env")
  etapa "Recriando o i1 (I1_P4_DIR=$I1_P4_DIR)"
  dc up -d --no-deps i1
  esperar_i1_pronto
}

p4_ligar_tmp() {
  if [[ "${1:-}" != --preparar ]]; then
    [[ -t 0 ]] || erro "o I1 não vê o /tmp da placa (onde o P4 cria o socket). Rode: ./inf_a4.sh p4 --preparar"
    echo "O I1 desta build não vê o /tmp da placa, onde o P4 cria $P4_SOCKET."
    echo "Contorno provisório: I1_P4_DIR=/tmp no $APP.local.env (fora do Git) e recriar o i1."
    local r; read -r -p "Aplicar agora? [s/N] " r
    [[ "$r" == [sS]* ]] || erro "nada mudou"
  fi
  if [[ -f "$APP.local.env" ]] && grep -q '^I1_P4_DIR=' "$APP.local.env"; then
    sed -i 's|^I1_P4_DIR=.*|I1_P4_DIR=/tmp|' "$APP.local.env"
  else
    printf '%s\nI1_P4_DIR=/tmp\n' "$P4_MARCA" >> "$APP.local.env"
  fi
  export I1_P4_DIR=/tmp
  recriar_i1
}

p4_desfazer() {
  if [[ -f "$APP.local.env" ]]; then
    local tmp; tmp=$(mktemp)
    grep -vxF -e "$P4_MARCA" -e 'I1_P4_DIR=/tmp' "$APP.local.env" > "$tmp" || true
    cat "$tmp" > "$APP.local.env"; rm -f "$tmp"
    grep -qvE '^[[:space:]]*(#|$)' "$APP.local.env" || rm -f "$APP.local.env"
  fi
  I1_P4_DIR=$(sed -n 's/^I1_P4_DIR=//p' "$APP.env")
  [[ -f "$APP.local.env" ]] && grep -q '^I1_P4_DIR=' "$APP.local.env" && I1_P4_DIR=$(sed -n 's/^I1_P4_DIR=//p' "$APP.local.env")
  export I1_P4_DIR
  ok "contorno desfeito ($APP.local.env $([[ -f "$APP.local.env" ]] && echo 'mantido com o resto' || echo 'removido'))"
  [[ -n "$(container_i1)" ]] && recriar_i1
  return 0
}

# Para o P4 que este script subiu (Ctrl+C nele). Se o socket que ESTA execução criou sobrar no /tmp,
# apaga (senão a próxima execução da SIS-2 seria recusada pelo P4); nunca toca na pasta do P4.
parar_p4() {
  [[ -n "$P4_PID" ]] || return 0
  local i
  sudo kill -INT "$P4_PID" 2>/dev/null || true
  for i in {1..10}; do vivo "$P4_PID" || break; sleep 1; done
  if vivo "$P4_PID"; then sudo kill -TERM "$P4_PID" 2>/dev/null || true; sleep 2; fi
  if vivo "$P4_PID"; then sudo kill -KILL "$P4_PID" 2>/dev/null || true; fi
  wait "$P4_PID" 2>/dev/null || true
  P4_PID=""
  [[ -e "$P4_SOCKET" ]] && como_p4 rm -f "$P4_SOCKET" 2>/dev/null || true
  echo "  P4 parado"
}

# Atraso publicado - capturado (ms), sequência e sessões das detecções de um source_id
resumo_tempos() {   # resumo_tempos <jsonl> <source_id> → "n mediana_ms max_ms sessões seq_min-seq_max"
  python3 - "$1" "$2" <<'PY'
import json, statistics, sys
from datetime import datetime
def t(s): return datetime.fromisoformat(s.replace("Z", "+00:00"))
lat, seq, sess = [], [], set()
for linha in open(sys.argv[1], encoding="utf-8"):
    try: m = json.loads(linha)
    except ValueError: continue
    if m.get("source_id") != sys.argv[2]: continue
    sess.add(m.get("session_id"))
    if isinstance(m.get("sequence"), int): seq.append(m["sequence"])
    try: lat.append((t(m["published_at"]) - t(m["captured_at"])).total_seconds() * 1000)
    except (KeyError, TypeError, ValueError): pass
if not lat:
    print("0 - - 0 -"); sys.exit()
faixa = f"{min(seq)}-{max(seq)}" if seq else "-"
print(len(lat), round(statistics.median(lat)), round(max(lat)), len(sess), faixa)
PY
}

p4_testar() {   # p4_testar [VIDEO] [QUADROS]
  local video=${1:-$P4_VIDEO} quadros=${2:-$INF_P4_QUADROS} equipe=${INF_P4_EQUIPE:-INV1}
  [[ "$quadros" =~ ^[0-9]+$ ]] || erro "QUADROS deve ser um número (recebi '$quadros')"
  local stem; stem=$(basename "$video"); stem=${stem%.*}
  local sid="file_$stem"   # o P4 põe este source_id no cabeçalho, e o I1 publica com ele

  etapa "Conferindo"
  aceite_conferir i1
  checar_kafka_local
  checar_i1_permanente
  local p
  for p in $I1_PACOTES; do engine_existe "$p" || erro "falta a engine de $p; rode ./inf_a4.sh engines antes"; done
  echo "  o P4 roda como '$P4_USUARIO' (sudo -u): pode pedir a sua senha"
  sudo -v || erro "preciso do sudo para rodar o P4 como $P4_USUARIO"
  como_p4 test -x "$P4_DIR/venv/bin/python" -a -x "$P4_DIR/scripts/p4_demo.sh" \
    || erro "não achei o P4 pronto em $P4_DIR (venv/bin/python e scripts/p4_demo.sh), lido como $P4_USUARIO"
  como_p4 test -f "$video" || erro "o $P4_USUARIO não acha o vídeo $video"
  local versao_p4 mudancas_p4
  versao_p4=$(como_p4 git -C "$P4_DIR" log -1 --format='%h %cs %s' 2>/dev/null || echo '?')
  mudancas_p4=$(como_p4 git --no-optional-locks -C "$P4_DIR" status --short 2>/dev/null | wc -l)
  ok "P4 em $P4_DIR: $versao_p4 ($mudancas_p4 arquivo(s) com mudança local)"
  if i1_ve_tmp_da_placa; then ok "o I1 vê o /tmp da placa (I1_P4_DIR=/tmp)"
  else p4_ligar_tmp "${P4_PREPARAR:-}"; fi

  # Um P4 de arquivo por vez (a trava é a do próprio p4_demo.sh)
  como_p4 flock -n "$P4_LOCK" true \
    || erro "já há um P4 de arquivo rodando nesta placa (trava $P4_LOCK ocupada). É da SIS-2? Combine antes de parar."
  # Socket sem P4 rodando: sobra de outra execução. Não é desta build: não apaga, só avisa.
  [[ ! -e "$P4_SOCKET" ]] || erro "existe $P4_SOCKET sem P4 rodando (sobra de outra execução; o P4 recusa subir com ele).
  Ele não é desta build: peça à SIS-2 para conferir e apagar ($(stat -c '%U, %y' "$P4_SOCKET" 2>/dev/null))."
  liberar_memoria

  local ts pasta rel c1 t0
  ts=$(date +%Y%m%d-%H%M%S)
  pasta="resultados/p4-i1-$ts"; rel="$pasta.txt"
  mkdir -p "$pasta"
  ANTES="$pasta/offsets-antes.txt"; DEPOIS="$pasta/offsets-depois.txt"
  c1=$(container_i1)
  offsets_brutos > "$ANTES"
  [[ -s "$ANTES" ]] || erro "não consegui contar as mensagens em $KAFKA_BROKER"

  etapa "P4: tocando $video como câmera (log em $pasta/p4.log)"
  # Encadeia com o trap da lib (arquivo temporário de segredos); parar_p4 pode rodar duas vezes
  local trap_lib; trap_lib=$(trap -p EXIT | sed "s/^trap -- '\(.*\)' EXIT\$/\1/")
  # shellcheck disable=SC2064
  trap "parar_p4; $trap_lib" EXIT
  sudo -u "$P4_USUARIO" bash -c "cd '$P4_DIR' && PYTHONDONTWRITEBYTECODE=1 P4_VIDEO_PATH='$video' exec ./scripts/p4_demo.sh video" \
    > "$pasta/p4.log" 2>&1 < /dev/null &
  P4_PID=$!
  local limite=$((SECONDS + 30)) sobe=1
  until [[ -S "$P4_SOCKET" ]]; do
    vivo "$P4_PID" || { sobe=0; break; }
    (( SECONDS < limite )) || { sobe=0; break; }
    sleep 1
  done
  if (( sobe )); then registrar T-P4A PASSOU "P4 subiu e criou o socket" "$P4_SOCKET; $(grep -m1 -E '^Vídeo:' "$pasta/p4.log" || true)"
  else registrar T-P4A FALHOU "P4 subiu e criou o socket" "sem $P4_SOCKET em 30 s; fim do log: $(tail -1 "$pasta/p4.log")"; fi

  local leu=0
  if (( sobe )); then
    echo "-- leitor de teste do próprio P4 (scripts/p4_ler.sh video)"
    if como_p4 bash -c "cd '$P4_DIR' && PYTHONDONTWRITEBYTECODE=1 ./scripts/p4_ler.sh video" > "$pasta/p4_ler.log" 2>&1 < /dev/null; then leu=1; fi
    if (( leu )); then registrar T-P4L PASSOU "P4: um quadro lido pela memória compartilhada" "p4_ler.sh ok ($pasta/p4_ler.log)"
    else registrar T-P4L FALHOU "P4: um quadro lido pela memória compartilhada" "$(tail -1 "$pasta/p4_ler.log")"; fi
  fi

  local sessao=0 comecou=0
  if (( sobe )); then
    etapa "I1: lendo do P4 (\"source\": \"video\"), $equipe, $quadros quadros"
    t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    publicar_comando "{\"action\": \"START\", \"squad\": \"$equipe\", \"source\": \"video\", \"source_id\": \"$sid\", \"max_frames\": $quadros}"
    sleep 5
    if docker logs --since "$t0" "$c1" 2>&1 | grep -q "START repetido para equipe ativa '$equipe'"; then
      aviso "a equipe $equipe já tinha uma sessão ativa no I1 (o A4?): o I1 ignorou a fonte deste pedido"
    fi
    esperar_sessao "$c1" "$equipe" "$t0" 300 && sessao=1
    docker logs --since "$t0" "$c1" > "$pasta/i1.log" 2>&1 || true
    grep -q "Carregando" "$pasta/i1.log" && comecou=1
  fi
  parar_p4
  sleep 10
  offsets_brutos > "$DEPOIS"

  etapa "Lendo as detecções novas"
  ler_novas ods.i1.detections "$pasta/i1.detections.jsonl"
  local c_i1 n_i1 versoes fim_sessao tempos
  c_i1=$(contrato "ods-i1-gpu:$I1_REF" python3 /app/schemas/ods.i1.detections.v1.0.schema.json "$pasta/i1.detections.jsonl" "$sid")
  read -r _ _ n_i1 _ <<<"$(grep '^CONTRATO' <<<"$c_i1")"
  versoes=$(sed -n 's/^VERSOES //p' <<<"$c_i1")
  fim_sessao=$(grep "Sessão '$equipe' encerrada" "$pasta/i1.log" 2>/dev/null | tail -1 | sed 's/.*encerrada/encerrada/' || true)
  tempos=$(resumo_tempos "$pasta/i1.detections.jsonl" "$sid" 2>/dev/null) || tempos="0 - - 0 -"

  if (( sessao )) && [[ "$fim_sessao" != *"(error)"* ]]; then registrar T-P4S PASSOU "I1 leu a sessão do P4 até o fim" "$fim_sessao"
  elif (( sessao )); then registrar T-P4S FALHOU "I1 leu a sessão do P4 até o fim" "$fim_sessao; $(grep -m1 'Erro ao executar' "$pasta/i1.log" | cut -c1-200)"
  elif (( comecou )); then registrar T-P4S FALHOU "I1 leu a sessão do P4 até o fim" "começou, sem 'Sessão $equipe encerrada' em 5 min ($pasta/i1.log)"
  else registrar T-P4S FALHOU "I1 leu a sessão do P4 até o fim" "o I1 não começou ($pasta/i1.log)"; fi
  if (( ${n_i1:-0} > 0 )); then registrar T-P4I PASSOU "I1 detecções vindas do P4" "$n_i1 mensagens com source_id $sid"
  else registrar T-P4I FALHOU "I1 detecções vindas do P4" "nenhuma com source_id $sid"; fi
  avaliar_contrato T-P4C "contrato ods.i1.detections (schema do I1)" "$c_i1"
  if (( ${n_i1:-0} == 0 )); then registrar T-P4G FALHOU "I1 na GPU (TensorRT)" "sem detecções do P4 para conferir"
  elif [[ -n "$versoes" && "$versoes" != *,* && "$versoes" == *-fp16 ]]; then registrar T-P4G PASSOU "I1 na GPU (TensorRT)" "artifact_version $versoes"
  else registrar T-P4G FALHOU "I1 na GPU (TensorRT)" "artifact_version '${versoes:-?}' (esperado …-fp16)"; fi
  local n med mx ns faixa
  read -r n med mx ns faixa <<<"$tempos"
  if (( n > 0 )); then registrar T-P4T INFO "tempo P4 → I1 (publicado − capturado)" "mediana $med ms, máx. $mx ms em $n mensagens; $ns sessão(ões) do P4; sequence $faixa"
  else registrar T-P4T INFO "tempo P4 → I1 (publicado − capturado)" "sem mensagens para medir"; fi

  local pa=0 f=0 linha
  for linha in "${RES[@]}"; do
    case "$(cut -d'|' -f2 <<<"$linha")" in PASSOU) pa=$((pa+1)) ;; FALHOU) f=$((f+1)) ;; esac
  done
  {
    echo "P4 (SIS-2) → I1 da build inf_a4 — $(date '+%Y-%m-%d %H:%M:%S') — $(uname -n)"
    echo "P4: $P4_DIR ($versao_p4; $mudancas_p4 mudança(s) local(is)) · vídeo $video · source_id $sid"
    echo "I1: ${I1_REF:0:7} · equipe $equipe · $quadros quadros · Kafka $KAFKA_BROKER"
    echo
    for linha in "${RES[@]}"; do
      IFS='|' read -r id r oque det <<<"$linha"
      printf '%-6s %-7s %-42s %s\n' "$id" "$r" "$oque" "$det"
    done
    echo
    echo "Obs.: com o P4 como fonte, o I1 publica com o source_id e o session_id do P4 ($sid), não com"
    echo "os do pedido. O A4 espera a câmera $equipe."
    echo
    echo "Resumo: PASSOU $pa, FALHOU $f"
  } | tee "$rel"
  echo
  echo "Relatório: $ODS_DIR_APP/$rel (logs do P4 e do I1 e mensagens em $pasta/)"
  echo "O contorno I1_P4_DIR=/tmp continua ativo; para desfazer: ./inf_a4.sh p4 --desfazer"
  (( f == 0 ))
}

# ---------------------------------------------------------------- status

status() {
  dc --profile engine --profile i3 ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  echo
  local c1; c1=$(container_i1)
  if [[ -n "$c1" ]]; then
    echo "I1 desta build: $(docker inspect -f '{{.State.Status}}, {{.RestartCount}} reinícios' "$c1")"
    echo "Últimos pedidos encerrados:"
    docker logs --tail 2000 "$c1" 2>&1 | grep -E "Sessão .* encerrada" | tail -5 | sed 's/^/  /' || echo "  nenhum"
  fi
  local cp; cp=$(container_i1_permanente)
  [[ -n "$cp" ]] && echo "I1 permanente (builds/i1) também de pé: Kafka $(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$cp" | sed -n 's/^ODS_KAFKA_BROKER=//p')"
  local ids
  mapfile -t ids < <(docker ps -q --filter label=com.docker.compose.project="$PROJETO")
  (( ${#ids[@]} )) && docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}}' "${ids[@]}" 2>/dev/null
  echo "Memória disponível: $(livre_ram_mb 2>/dev/null) MB"
  echo
  echo "Vídeos na pasta original ($I1_VIDEOS_ORIGINAL): $(listar_originais | tr '\n' ' ')"
  echo "Vídeos do P3 em /videos-p3 ($VIDEO_DIR): $(find "$VIDEO_DIR" -maxdepth 1 -name "*.mp4" -printf "%f " 2>/dev/null | sort)"
  echo
  echo "Engines em $I1_ENGINES_DIR:"
  local p
  for p in $I1_PACOTES; do
    if engine_existe "$p"; then echo "  ✔ $p"; else echo "  ✘ $p (./inf_a4.sh engines)"; fi
  done
  echo
  df -h /
  echo
  docker ps -a --filter name="^${KAFKA_LOCAL_CONTAINER:-kafka}\$" --format 'Kafka da turma na placa: {{.Status}}'
  echo "Kafka da build: $KAFKA_BROKER ($([[ -f inf_a4.local.env ]] && echo 'do inf_a4.local.env' || echo 'do inf_a4.env'))"
  local rel
  # shellcheck disable=SC2012
  rel=$(ls -t resultados/aceite-inf_a4-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

case "${1:-subir}" in
  i1)      shift; checar_kafka; pedir_i1 "$@" ;;
  comando) shift; checar_kafka; publicar_comando "${1:?uso: ./inf_a4.sh comando '{\"action\": \"STOP\", \"squad\": \"INV1\"}'}" ;;
  i3)      rodar i3 i3 ;;
  p4)      shift
           case "${1:-}" in
             --desfazer) p4_desfazer ;;
             --preparar) shift; P4_PREPARAR=--preparar p4_testar "$@" ;;
             *)          p4_testar "$@" ;;
           esac ;;
  engines) checar_gpu; checar_pasta "$I1_ENGINES_DIR" "engines TensorRT"; checar_disco; preparar_engines ;;
  contar)  contar ;;
  repos)   shift; exec "$ODS_DIR_BUILDS/../validacao/inf/testar-inf-repos.sh" --build "$APP" "$@" ;;
  log)     shift; dc logs -f --tail 50 "${1:?uso: ./inf_a4.sh log <serviço>}" ;;
  *)       ods_principal "$@" ;;
esac
