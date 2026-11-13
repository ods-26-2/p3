#!/usr/bin/env bash
# Fluxo do A4 pela API do árbitro: saúde e Kafka, proteção por token, consultas, player e
# interface. Não cria partidas (não há rota para apagá-las); isso fica no a4.sh testar.
APP=a4
# shellcheck source=../validacao-geral/fluxo-comum.sh
source "$(dirname "$(readlink -f "$0")")/../validacao-geral/fluxo-comum.sh"
API=${API:-http://127.0.0.1:8000}; WEB=${WEB:-http://127.0.0.1:3000}
TOKEN=$(segredo A4_TOKEN)

req "saúde da API" 200 GET "$API/health" && {
  confere "Kafka ligado no A4" 'd["kafka_habilitado"] is True'
  confere "modo demonstração desligado" 'd["modo_demo"] is False'
  confere "token do árbitro exigido" 'd["token"] is True'
  cal=$(campo 'd["calibracoes_carregadas"]'); [[ "$cal" != "[]" ]] && ok "calibrações carregadas: $cal" || aviso "nenhuma calibração (rode builds/a4/a4.sh calibrar)"
}
req "criar partida sem token é recusado" 401 POST "$API/partidas" '{"time_a":"ZZ","time_b":"ZZ"}'
req "criar partida com token errado é recusado" 401 POST "$API/partidas" '{"time_a":"ZZ","time_b":"ZZ"}' "zz-token-errado"
[[ -n "$TOKEN" ]] && req "câmera com ângulo fora da faixa é recusada (com token)" 422 POST "$API/camera/enquadrar?pan_deg=200&tilt_deg=0" "" "$TOKEN"
req "partida inexistente devolve 404" 404 GET "$API/partidas/zz-validacao-inexistente"
req "estado da câmera (P7)" 200 GET "$API/camera/estado"
req "estado do player (P6/vídeo)" 200 GET "$API/p6" && confere "vídeo da quadra encontrado" 'd["video"] is not None'
req "interface do árbitro" 200 GET "$WEB/"
fim
