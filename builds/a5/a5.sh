#!/usr/bin/env bash
# a5.sh — monta e sobe a build do A5 · EPI / segurança (VER-3) na Jetson (P3 / SIS-1).
#
#   ./a5.sh                o mesmo que ./a5.sh subir
#   ./a5.sh subir          confere a placa, baixa o código, constrói o que falta, sobe tudo e
#                          prepara a engine TensorRT do I1 (minutos só na primeira vez)
#   ./a5.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a5.sh cadeia         sobe também I9, I2 e S1 (perfil "cadeia")
#   ./a5.sh video          sobe a cadeia e toca VIDEO_DIR/VIDEO_ARQUIVO pelo P4 + I1 (GPU, modelo de EPI)
#   ./a5.sh status         containers, disco e Kafka da turma
#   ./a5.sh parar          derruba a build (mantém banco do A5, histórico do S3 e clipes)
#   ./a5.sh testar         teste de aceitação (inclui o vídeo) → resultados/aceite-a5-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a5
SEGREDOS=(A5_ADMIN_SENHA)
# O I1 (GPU, a maior imagem) vai por último e sozinho. Se a imagem ods-i1-gpu:<I1_REF> do A8
# ainda estiver na placa, ele não é reconstruído (mesmo commit, mesma imagem).
ETAPAS=("s4 aceite" "a5-backend s3 i9 i2 s1 p4" "a5-frontend" "i1")

# ---------------------------------------------------------------- GPU (o mesmo do a8.sh)

# O Docker precisa do runtime "nvidia" (nvidia-container-toolkit do JetPack) para o I1.
checar_gpu() {
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' \
    || erro "o Docker desta placa não tem o runtime nvidia; o I1 (TensorRT) não sobe sem ele.
  Confira com: docker info | grep -i runtime"
  ok "Docker com runtime nvidia (GPU para o I1)"
}

# A pasta das engines é criada aqui (senão o Docker a cria como root e o i1-engine não grava).
checar_pasta_engines() {
  [[ -d "$I1_ENGINES_DIR" ]] && return 0
  if mkdir -p "$I1_ENGINES_DIR" 2>/dev/null; then ok "pasta criada: $I1_ENGINES_DIR"
  else aviso "não consegui criar $I1_ENGINES_DIR. Uma vez só: sudo mkdir -p $I1_ENGINES_DIR && sudo chown $(id -un) $I1_ENGINES_DIR"; fi
}

# Engine TensorRT do I1: compila na primeira vez (~7 min); depois só confere (segundos).
preparar_engine_i1() {
  etapa "Engine TensorRT do I1 ($I1_PACOTE em $I1_ENGINES_DIR)"
  # Compilar a engine também precisa de memória da GPU: com a pilha do A5 de pé, o p2-build
  # imprimiu dezenas de "NvMapMemAllocInternalTagged ... error 12" (Jetson, 17/11/2026).
  # Só esvazia o cache se a engine ainda não existe (senão a conferência leva segundos).
  [[ -d "$I1_ENGINES_DIR/${I1_PACOTE/\//-}" ]] || liberar_memoria
  dc --profile video run --rm i1-engine || erro "a engine do I1 não ficou pronta; veja a saída acima"
  checar_disco
}

# A Jetson divide a RAM entre CPU e GPU; com pouca memória livre o TensorRT do I1 falha ao criar
# o contexto (OUT_OF_MEMORY) e só entra depois de reinícios (A8, Jetson, 14/11/2026). Esvaziar o
# cache de páginas não apaga dados: o kernel só descarta cópias de arquivos que estão no disco.
liberar_memoria() {
  local antes depois
  antes=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
  local cmd='sync; echo 3 > /proc/sys/vm/drop_caches'
  if { [[ -t 0 ]] && sudo sh -c "$cmd"; } || sudo -n sh -c "$cmd" 2>/dev/null; then
    depois=$(awk '/^MemFree/ {print int($2/1024)}' /proc/meminfo)
    ok "memória livre para a GPU: ${antes} MB → ${depois} MB (cache de páginas esvaziado)"
  else
    aviso "memória livre: ${antes} MB. Sem sudo para esvaziar o cache; o I1 pode falhar ao carregar
  a engine e precisar de reinícios. À mão: sudo sh -c '$cmd'"
  fi
}

# Toca o vídeo uma vez (P4 + I1) e espera o P4 terminar.
tocar_video() {
  liberar_memoria
  dc --profile cadeia --profile video up -d --force-recreate p4 i1 >/dev/null
  docker wait "$(dc --profile video ps -aq p4)" >/dev/null
  ok "vídeo terminou ($VIDEO_ARQUIVO, source_id $VIDEO_SOURCE_ID)"
}

# ---------------------------------------------------------------- ganchos da lib

checar_entradas() {
  # O backend recusa senha com menos de 4 caracteres e cai na partida, em laço de reinícios
  # ("ValueError: A senha precisa de pelo menos 4 caracteres", Jetson, 17/11/2026).
  local senha
  senha=$(grep -E '^A5_ADMIN_SENHA=' a5.secrets.env | cut -d= -f2-)
  (( ${#senha} >= 4 )) || erro "A5_ADMIN_SENHA em a5.secrets.env precisa de pelo menos 4 caracteres (tem ${#senha})"
  checar_gpu
  checar_pasta_engines
  entrada_arquivo "$VIDEO_DIR/$VIDEO_ARQUIVO" "vídeo de EPI (pessoas com/sem capacete e colete)" \
    "o P4 não tem o que tocar e o S4 fica sem evidência"
  # O P4 publica com source_id "file_<nome sem extensão>"; zonas e teste usam VIDEO_SOURCE_ID.
  local esperado="file_${VIDEO_ARQUIVO%.*}"
  [[ "$VIDEO_SOURCE_ID" == "$esperado" ]] \
    || erro "VIDEO_SOURCE_ID=$VIDEO_SOURCE_ID, mas o P4 vai publicar $esperado (de $VIDEO_ARQUIVO). Acerte o a5.env."
  grep -q "\"$VIDEO_SOURCE_ID\"" artefatos/zones-a5-p3-1.json \
    || aviso "as zonas (artefatos/zones-a5-p3-1.json) não citam $VIDEO_SOURCE_ID: o S1 não vai ligar as posições à zona"
  return 0
}

pos_subida() {
  # O nginx do front (nginx.conf do VER-3) resolve "backend" uma vez, ao subir, e guarda o IP.
  # Se o backend foi recriado depois (senha nova, imagem nova), o IP muda e o nginx responde 502
  # (Jetson, 17/11/2026). Reiniciar o front faz ele resolver de novo; leva ~1 s.
  local ini_back ini_front
  ini_back=$(docker inspect -f '{{.State.StartedAt}}' "$(dc ps -q a5-backend)")
  ini_front=$(docker inspect -f '{{.State.StartedAt}}' "$(dc ps -q a5-frontend)")
  if [[ "$ini_front" < "$ini_back" ]]; then
    dc restart a5-frontend >/dev/null
    local i=0
    until curl -s -o /dev/null -m 2 http://127.0.0.1:8095/ || (( ++i >= 15 )); do sleep 1; done
    ok "frontend reiniciado (o backend foi recriado depois dele)"
  fi
  checar_http "http://127.0.0.1:8095/" "interface do A5"
  checar_http "http://127.0.0.1:8095/health" "API do A5 (pelo nginx)"
  preparar_engine_i1
  ok "interface do A5: http://$JETSON_IP:8095  (usuário administrador; senha em a5.secrets.env)"
}

testar() {
  aceite_conferir a5-backend s3 s4
  etapa "Cadeia de EPI (I9, I2, S1)"
  dc --profile cadeia up -d i9 i2 s1 >/dev/null
  aceite_iniciar

  # O teste faz primeiro os itens com entrada simulada (S2 -> S3 -> A5 e o clipe do S4) e só
  # depois pede o vídeo: a sessão nova do P4 esvazia o buffer do S4 e atrapalharia o C03.
  etapa "Esperando os itens simulados (C01–C08)"
  local limite=$((SECONDS + 600))
  until dc --profile aceite logs aceite 2>/dev/null | grep -q "passo externo 'video'"; do
    [[ "$(dc --profile aceite ps -a --format '{{.State}}' aceite)" == running ]] || break
    (( SECONDS < limite )) || { aviso "o teste não pediu o vídeo em 10 minutos"; break; }
    sleep 3
  done

  etapa "Vídeo: P4 tocando e I1 (GPU, $I1_PACOTE) detectando"
  tocar_video
  sleep 10
  aceite_passo video

  # O S4 lê o MP4 por conta própria e esvazia o buffer a cada sessão nova do P4.
  dc restart s4 >/dev/null
  ok "S4 reiniciado (buffer de vídeo de volta)"
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

case "${1:-}" in
  cadeia) dc --profile cadeia up -d i9 i2 s1 ;;
  video)  checar_pasta_engines; dc --profile cadeia up -d i9 i2 s1 && preparar_engine_i1 && tocar_video ;;
  *)      ods_principal "$@" ;;
esac
