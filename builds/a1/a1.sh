#!/usr/bin/env bash
# a1.sh — monta e sobe a build do A1 · Indústria / inspeção (VER-1) na Jetson (P3 / SIS-1).
#
#   ./a1.sh                o mesmo que ./a1.sh subir
#   ./a1.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a1.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a1.sh i8             o I8 publica os 4 eventos de exemplo; o A1 deve registrar 4 inspeções
#   ./a1.sh status         containers, disco e Kafka da turma
#   ./a1.sh parar          derruba a build (mantém banco e clipes)
#   ./a1.sh testar         teste de aceitação → resultados/aceite-a1-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a1
SEGREDOS=(A1_DB_PASSWORD)
ETAPAS=("s4 aceite" "a1-backend a1-frontend i8")

checar_entradas() {
  entrada_arquivo "$VIDEO_DIR/$VIDEO_ARQUIVO" "vídeo da linha (S4)" "o S4 sobe sem vídeo de onde recortar evidência"
}

pos_subida() {
  checar_http "http://127.0.0.1:8010/api/v1/health" "API do A1"
  checar_http "http://127.0.0.1:${A1_PORTA:-5500}/frontend/" "interface do A1"
  ok "interface de inspeção: http://$JETSON_IP:${A1_PORTA:-5500}/frontend/"
  echo "Para publicar eventos de exemplo do I8: ./a1.sh i8"
}

testar() {
  aceite_conferir a1-backend s4
  aceite_iniciar
  etapa "I8 publicando os 4 eventos de exemplo"
  dc --profile i8 run --rm i8 || aviso "o publisher do I8 terminou com erro"
  aceite_passo i8
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

case "${1:-}" in
  i8) dc --profile i8 run --rm i8 ;;
  *)  ods_principal "$@" ;;
esac
