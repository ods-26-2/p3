#!/usr/bin/env bash
# i1.sh — build dedicada do I1 (detecção, MOD-1): serviço permanente na Jetson (P3 / SIS-1).
#
#   ./i1.sh                o mesmo que ./i1.sh subir
#   ./i1.sh subir          confere a placa, baixa o código, constrói a imagem (se faltar), sobe o
#                          orquestrador e prepara a engine de cada pacote de I1_PACOTES
#   ./i1.sh subir --reconstruir   reconstrói a imagem mesmo que ela já exista
#   ./i1.sh engines        só confere/compila as engines (ex.: depois de mudar I1_PACOTES)
#   ./i1.sh videos         copia os vídeos de assets/ (raiz do p3) para VIDEO_DIR e cria os links
#                          <SQUAD>.mp4 de I1_VIDEOS (também roda no "subir")
#   ./i1.sh comando '<json>'      manda um comando em ods.i1.command
#                          ex.: ./i1.sh comando '{"action": "START", "squad": "VER5"}'
#   ./i1.sh log            acompanha o log do orquestrador (Ctrl+C para sair)
#   ./i1.sh testar         teste de aceitação → resultados/aceite-i1-*.txt|json
#   ./i1.sh status         container, engines, vídeos, últimos pedidos, disco e Kafka
#   ./i1.sh parar          derruba a build (o I1 deixa de atender todas as aplicações)
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Guia de teste: validacao/i1/GUIA-BUILD-I1.md
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=i1
SEGREDOS=()
ETAPAS=("i1")
ONESHOT=(kafka-topicos)

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

# ---------------------------------------------------------------- conferências

checar_gpu() {
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' \
    || erro "o Docker desta placa não tem o runtime nvidia; o I1 (TensorRT) não sobe sem ele.
  Confira com: docker info | grep -i runtime"
  ok "Docker com runtime nvidia (GPU para o I1)"
}

# Pastas do host montadas no I1. Criadas aqui: se faltarem, o Docker as cria como root (e o
# i1-engine ou o P4 de outra build não gravariam nelas).
checar_pasta() {   # checar_pasta <pasta> <para quê>
  [[ -d "$1" ]] && return 0
  if mkdir -p "$1" 2>/dev/null; then ok "pasta criada: $1 ($2)"
  else erro "não consegui criar $1 ($2). Uma vez só: sudo mkdir -p $1 && sudo chown $(id -un) $1"; fi
}

# Vídeos das equipes: assets/ do p3 (versionado) -> VIDEO_DIR, com o link <SQUAD>.mp4 que o
# orquestrador procura quando o comando não traz "source". Links relativos, dentro da própria
# pasta: um link para fora dela não existiria dentro do container. Idempotente.
ASSETS_DIR=$(readlink -f "$ODS_DIR_BUILDS/../assets")
instalar_videos() {
  checar_pasta "$VIDEO_DIR" "vídeos das equipes"
  [[ -w "$VIDEO_DIR" ]] || erro "sem permissão de escrita em $VIDEO_DIR. Uma vez só: sudo chown $(id -un) $VIDEO_DIR"
  local par squad video origem alvo
  for par in $I1_VIDEOS; do
    squad=${par%%=*}; video=${par#*=}
    origem="$ASSETS_DIR/$video"
    if [[ -f "$origem" ]] && ! cmp -s "$origem" "$VIDEO_DIR/$video"; then
      cp -f "$origem" "$VIDEO_DIR/$video.tmp" && mv -f "$VIDEO_DIR/$video.tmp" "$VIDEO_DIR/$video"
      ok "vídeo copiado: assets/$video → $VIDEO_DIR/$video"
    fi
    if [[ ! -f "$VIDEO_DIR/$video" ]]; then
      aviso "sem $VIDEO_DIR/$video (nem em assets/): o $squad fica sem vídeo; o teste usa o do VER5"
      continue
    fi
    alvo="$VIDEO_DIR/$squad.mp4"
    if [[ "$video" == "$squad.mp4" ]]; then
      ok "vídeo do $squad: $alvo"
    elif [[ -e "$alvo" && ! -L "$alvo" ]]; then
      aviso "$alvo é um arquivo, não um link para $video; mantido como está"
    else
      ln -sfn "$video" "$alvo"
      ok "vídeo do $squad: $alvo → $video"
    fi
  done
}

checar_entradas() {
  checar_gpu
  checar_pasta "$I1_ENGINES_DIR" "engines TensorRT"
  checar_pasta "$I1_P4_DIR" "sockets do P4 de outra build"
  instalar_videos
}

engine_existe() { [[ -d "$I1_ENGINES_DIR/${1/\//-}" ]]; }

# A Jetson divide a RAM entre CPU e GPU: com pouca memória livre, o TensorRT falha ao criar o
# contexto ("NvMap ... error 12", OUT_OF_MEMORY). Esvaziar o cache de páginas não apaga dados.
liberar_memoria() {
  local antes depois
  antes=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
  local cmd='sync; echo 3 > /proc/sys/vm/drop_caches'
  if { [[ -t 0 ]] && sudo sh -c "$cmd"; } || sudo -n sh -c "$cmd" 2>/dev/null; then
    depois=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
    ok "memória livre para a GPU: ${antes} MB → ${depois} MB (cache de páginas esvaziado)"
  else
    aviso "memória livre: ${antes} MB. Sem sudo para esvaziar o cache; o TensorRT pode faltar memória.
  À mão: sudo sh -c '$cmd'"
  fi
}

# ---------------------------------------------------------------- engines

preparar_engines() {
  etapa "Engines TensorRT do I1 ($I1_PACOTES) em $I1_ENGINES_DIR"
  local p faltam=()
  for p in $I1_PACOTES; do engine_existe "$p" || faltam+=("$p"); done
  if (( ${#faltam[@]} )); then
    echo "  a compilar: ${faltam[*]} (~7 min cada na primeira vez)"
    # Compilar também usa memória da GPU (A5, 17/11/2026: "NvMap ... error 12" com a pilha de pé).
    liberar_memoria
  fi
  dc --profile engine run --rm i1-engine || erro "as engines do I1 não ficaram prontas; veja a saída acima"
  checar_disco
}

# ---------------------------------------------------------------- depois do "up"

container_i1() { dc ps -aq i1 2>/dev/null | head -1; }

pos_subida() {
  preparar_engines
  etapa "Orquestrador"
  local limite=$((SECONDS + 60)) c
  c=$(container_i1)
  until docker logs "$c" 2>&1 | grep -q 'Aguardando comandos'; do
    (( SECONDS < limite )) || { docker logs --tail 30 "$c" 2>&1; erro "o orquestrador não ficou pronto em 1 minuto"; }
    sleep 2
  done
  ok "I1 pronto: $(docker logs "$c" 2>&1 | grep 'Aguardando comandos' | tail -1)"
  echo
  echo "Pedidos pelo Kafka ($KAFKA_BROKER), tópico $I1_COMMAND_TOPIC, por exemplo:"
  echo "  ./i1.sh comando '{\"action\": \"START\", \"squad\": \"VER5\", \"source_id\": \"teste-manual\", \"max_frames\": 50}'"
  echo "Detecções em ods.i1.detections (source_id = o do comando, ou o nome da equipe)."
}

# ---------------------------------------------------------------- comandos extras

# Manda um comando pelo utilitário do próprio I1 (--send-command), na imagem do I1, sem GPU.
enviar_comando() {
  local json=${1:?uso: ./i1.sh comando '{"action": "START", "squad": "VER5"}'}
  # O serviço aceite monta ./resultados: sem a pasta, o Docker a criaria como root.
  mkdir -p resultados
  dc --profile aceite run --rm --no-deps -T --entrypoint python3 aceite \
    -u /app/I1/run_orchestrator.py --broker "$KAFKA_BROKER" --command-topic "$I1_COMMAND_TOPIC" \
    --send-command "$json"
}

# Há um pedido em andamento? (último "Carregando" sem "encerrada" depois dele)
ocupado() {
  docker logs --tail 2000 "$(container_i1)" 2>&1 | awk '
    /\[I1-ORCH\] Carregando/ { ativo = $0 }
    /\[I1-ORCH\] Sessão .* encerrada/ { ativo = "" }
    END { if (ativo != "") { print ativo; exit 0 } exit 1 }'
}

# ---------------------------------------------------------------- teste

testar() {
  etapa "Conferindo"
  aceite_conferir i1
  local c; c=$(container_i1)
  local p
  for p in $I1_PACOTES; do engine_existe "$p" || erro "falta a engine de $p; rode ./i1.sh engines antes"; done
  ok "engines de todos os pacotes presentes"
  local ativo
  if ativo=$(ocupado); then
    aviso "o I1 está atendendo outro pedido agora; os pedidos do teste vão para a fila:
  $ativo"
  fi
  liberar_memoria

  local t0 antes
  t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  antes=$(docker inspect -f '{{.RestartCount}}' "$c")
  aceite_iniciar

  etapa "Pedidos ao I1 (carga de cada pacote, fila, STOP, TTL, HEARTBEAT)"
  local limite=$((SECONDS + 1800))
  until dc --profile aceite logs aceite 2>/dev/null | grep -q PEDE_LOG; do
    [[ "$(dc --profile aceite ps -a --format '{{.State}}' aceite)" == running ]] || break
    (( SECONDS < limite )) || erro "o teste não pediu o log em 30 minutos"
    sleep 3
  done
  {
    echo "RESTARTS_ANTES=$antes"
    echo "RESTARTS_DEPOIS=$(docker inspect -f '{{.RestartCount}}' "$c")"
    docker logs --since "$t0" "$c" 2>&1
  } > resultados/.i1-log.txt
  aceite_passo log
  local codigo=0
  aceite_concluir || codigo=$?
  rm -f resultados/.i1-log.txt
  return "$codigo"
}

# ---------------------------------------------------------------- status

status() {
  dc --profile engine --profile aceite ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  local c; c=$(container_i1)
  if [[ -n "$c" ]]; then
    echo
    echo "Reinícios do i1: $(docker inspect -f '{{.RestartCount}}' "$c")"
    docker stats --no-stream --format 'Memória do i1: {{.MemUsage}}' "$c" 2>/dev/null || true
    local ativo
    if ativo=$(ocupado); then echo "Atendendo agora: ${ativo#*\[I1-ORCH\] }"; else echo "Atendendo agora: nada (GPU livre)"; fi
    echo "Últimos pedidos encerrados:"
    docker logs --tail 2000 "$c" 2>&1 | grep -E "Sessão .* encerrada" | tail -5 | sed 's/^/  /' || echo "  nenhum"
  fi
  echo
  echo "Vídeos em $VIDEO_DIR:"
  local par
  for par in $I1_VIDEOS; do
    if [[ -f "$VIDEO_DIR/${par%%=*}.mp4" ]]; then echo "  ✔ ${par%%=*}.mp4 ($(readlink "$VIDEO_DIR/${par%%=*}.mp4" || echo arquivo))"
    else echo "  ✘ ${par%%=*}.mp4 (rode ./i1.sh videos)"; fi
  done
  echo
  echo "Engines em $I1_ENGINES_DIR:"
  local p
  for p in $I1_PACOTES; do
    if engine_existe "$p"; then echo "  ✔ $p"; else echo "  ✘ $p (rode ./i1.sh engines)"; fi
  done
  echo
  df -h /
  echo
  echo "Kafka: $KAFKA_BROKER ($([[ -f i1.local.env ]] && echo 'do i1.local.env' || echo 'do i1.env'))"
  local rel; rel=$(ls -t resultados/aceite-i1-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

case "${1:-subir}" in
  videos)  instalar_videos ;;
  engines) checar_gpu; checar_pasta "$I1_ENGINES_DIR" "engines TensorRT"; checar_disco; preparar_engines ;;
  comando) shift; enviar_comando "${1:-}" ;;
  log)     docker logs -f --tail 50 "$(container_i1)" ;;
  *)       ods_principal "$@" ;;
esac
