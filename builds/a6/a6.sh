#!/usr/bin/env bash
# a6.sh — monta e sobe a build do A6 · Libras / acessibilidade (APL-2) na Jetson (P3 / SIS-1).
#
#   ./a6.sh                o mesmo que ./a6.sh subir
#   ./a6.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a6.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a6.sh amostra        o publicador do I4 manda o sinal I4_AMOSTRA_SINAL (a6.env) para o A6
#   ./a6.sh status         containers, disco e Kafka da turma
#   ./a6.sh parar          derruba a build (mantém as trajetórias)
#   ./a6.sh testar         teste de aceitação → resultados/aceite-a6-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a6
SEGREDOS=()
ETAPAS=("a6 s6 aceite")

checar_entradas() {
  [[ -f "$SRC_DIR/i4/lexicon/lexicon-$I4_AMOSTRA_SINAL.parquet" ]] || [[ ! -d "$SRC_DIR/i4" ]] \
    || aviso "não existe lexicon-$I4_AMOSTRA_SINAL.parquet no I4: ./a6.sh amostra vai falhar"
  return 0
}

pos_subida() {
  checar_http "http://127.0.0.1:${A6_PORTA:-8086}/" "tradutor do A6"
  ok "tradutor do A6: http://$JETSON_IP:${A6_PORTA:-8086}"
  echo "Para simular um sinal reconhecido pelo I4: ./a6.sh amostra"
}

testar() {
  aceite_conferir a6 s6
  aceite_iniciar
  etapa "I4: publicando o sinal $I4_AMOSTRA_SINAL"
  dc --profile i4 run --rm i4-amostra || aviso "o publicador do I4 terminou com erro"
  aceite_passo amostra
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

case "${1:-}" in
  amostra) dc --profile i4 run --rm i4-amostra ;;
  *)       ods_principal "$@" ;;
esac
