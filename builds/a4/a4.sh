#!/usr/bin/env bash
# a4.sh — monta e sobe a build do A4 · Esporte / arbitragem (INV-1) na Jetson (P3 / SIS-1).
#
#   ./a4.sh                o mesmo que ./a4.sh subir
#   ./a4.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a4.sh subir --reconstruir   reconstrói todas as imagens (obrigatório se mudar o JETSON_IP)
#   ./a4.sh calibrar       o I3 publica a calibração da quadra (rode uma vez antes do vídeo)
#   ./a4.sh video          toca VIDEO_DIR/VIDEO_ARQUIVO pelo P4 e o I1 procura a bola
#   ./a4.sh cadeia         sobe também o S5 (perfil "cadeia")
#   ./a4.sh status         containers, disco e Kafka da turma
#   ./a4.sh parar          derruba a build (mantém partidas e clipes)
#   ./a4.sh testar         teste de aceitação → resultados/aceite-a4-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a4
SEGREDOS=(A4_TOKEN)
# O front (Next.js) é a construção mais pesada: sozinho e por último.
ETAPAS=("s4 aceite" "a4-back i2 s1 i3 p4" "i1" "a4-front")

checar_entradas() {
  entrada_arquivo "$VIDEO_DIR/$VIDEO_ARQUIVO" "vídeo da quadra" "sem vídeo para o P4, o S4 e o player do A4"
  [[ "$VIDEO_SOURCE_ID" == "file_${VIDEO_ARQUIVO%.*}" ]] \
    || aviso "VIDEO_SOURCE_ID ($VIDEO_SOURCE_ID) não bate com o P4 (file_${VIDEO_ARQUIVO%.*}): a calibração não vai casar"
  entrada_arquivo "$I3_CSV" "correspondências do I3" "./a4.sh calibrar não vai funcionar"
}

pos_subida() {
  checar_http "http://127.0.0.1:8000/docs" "API do A4"
  checar_http "http://127.0.0.1:3000/" "interface do A4"
  ok "interface do árbitro: http://$JETSON_IP:3000  ·  API: http://$JETSON_IP:8000/docs"
  echo "Antes do primeiro vídeo: ./a4.sh calibrar  ·  depois: ./a4.sh video"
}

testar() {
  aceite_conferir a4-back i2 s1 s4
  [[ -f "$VIDEO_DIR/$VIDEO_ARQUIVO" ]] || erro "sem $VIDEO_DIR/$VIDEO_ARQUIVO para o P4 tocar"
  aceite_iniciar
  etapa "Calibração da quadra (I3)"
  dc --profile i3 run --rm -T i3 || aviso "o I3 terminou com erro"
  aceite_passo calibrar
  etapa "Vídeo: P4 tocando e I1 procurando a bola"
  dc --profile video up -d --force-recreate p4 i1 >/dev/null
  docker wait "$(dc --profile video ps -aq p4)" >/dev/null
  ok "vídeo terminou"
  # O S4 lê o MP4 por conta própria e esvazia o buffer a cada sessão nova do P4 (como no A8).
  dc restart s4 >/dev/null
  aceite_passo video
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

case "${1:-}" in
  calibrar) dc --profile i3 run --rm -T i3 ;;
  video)    dc --profile video up -d --force-recreate p4 i1 ;;
  cadeia)   dc --profile cadeia up -d s5 ;;
  *)        ods_principal "$@" ;;
esac
