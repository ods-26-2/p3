#!/usr/bin/env bash
# Fluxo do A3: o painel é Streamlit e não tem API própria; confere saúde e página.
# A decisão de risco é testada pelo Kafka (builds/a3/a3.sh testar).
APP=a3
# shellcheck source=../validacao-geral/fluxo-comum.sh
source "$(dirname "$(readlink -f "$0")")/../validacao-geral/fluxo-comum.sh"
WEB=${WEB:-http://127.0.0.1:8501}

req "saúde do Streamlit" 200 GET "$WEB/_stcore/health"
req "página do painel" 200 GET "$WEB/"
broker=$(docker exec ods-a3-a3-1 printenv ODS_KAFKA_FORCAR_BROKER 2>/dev/null)
[[ -n "$broker" ]] && ok "contorno do broker fixo ativo (Kafka $broker)" || falha "contorno do broker fixo ausente no container do A3"
fim
