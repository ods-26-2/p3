#!/usr/bin/env bash
# Fluxo do A1 pela API: saúde (banco, consumidor Kafka, S4), consultas de inspeção e o proxy do
# nginx da interface. Só leitura: as inspeções nascem do I8 (teste: builds/a1/a1.sh testar).
APP=a1
# shellcheck source=../validacao-geral/fluxo-comum.sh
source "$(dirname "$(readlink -f "$0")")/../validacao-geral/fluxo-comum.sh"
API=${API:-http://127.0.0.1:8010/api/v1}; WEB=${WEB:-http://127.0.0.1:5500}

req "saúde da API" 200 GET "$API/health" && {
  confere "API ONLINE (banco, consumidor Kafka e S4 de pé)" 'd["status"] == "ONLINE"'
  for comp in database kafka s4; do
    estado=$(campo "next((c['status'] for c in d['components'] if '$comp' in c['name'].lower()), '?')")
    [[ "$estado" == UP ]] && ok "componente $comp: UP" || aviso "componente $comp: $estado"
  done
}
req "lista de inspeções" 200 GET "$API/inspections?limit=5" && n=$(campo 'd["total"]') && ok "inspeções no banco: $n"
req "fila de revisão" 200 GET "$API/inspections/review-queue?limit=5"
req "inspeção inexistente devolve 404" 404 GET "$API/inspections/zz-validacao-inexistente"
if [[ "${n:-0}" -gt 0 ]]; then
  req "lista de inspeções (de novo)" 200 GET "$API/inspections?limit=1" >/dev/null
  id=$(campo 'd["items"][0]["inspection_id"]')
  req "detalhe da inspeção $id" 200 GET "$API/inspections/$id"
  req "histórico da inspeção $id" 200 GET "$API/inspections/$id/history"
else
  aviso "sem inspeções para ler o detalhe (rode builds/a1/a1.sh i8)"
fi
req "interface (nginx)" 200 GET "$WEB/frontend/"
req "API pelo proxy do nginx (alias backend)" 200 GET "$WEB/api/v1/health"
fim
