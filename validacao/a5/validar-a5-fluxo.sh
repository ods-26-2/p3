#!/usr/bin/env bash
# Fluxo do A5 pelo nginx da interface (8095, que repassa /api/ ao backend): login, controle de
# acesso e consultas. Só leitura: cadastrar EPI republica o catálogo no Kafka para o I9 e o S2.
APP=a5
# shellcheck source=../validacao-geral/fluxo-comum.sh
source "$(dirname "$(readlink -f "$0")")/../validacao-geral/fluxo-comum.sh"
WEB=${WEB:-http://127.0.0.1:8095}; API=$WEB/api
SENHA=$(segredo A5_ADMIN_SENHA)

req "interface" 200 GET "$WEB/"
req "saúde do backend pelo nginx" 200 GET "$WEB/health"
req "login com senha errada é recusado" 401 POST "$API/auth/login" '{"id":"administrador","senha":"zz-senha-errada"}'
req "alertas sem login são recusados" 401 GET "$API/alertas"
if req "login do administrador" 200 POST "$API/auth/login" "{\"id\":\"administrador\",\"senha\":\"$SENHA\"}"; then
  TK=$(campo 'd["token"]')
  req "sessão do administrador" 200 GET "$API/auth/eu" "" "$TK" && confere "usuário é o administrador" 'd["id"] == "administrador"'
  req "alertas ativos (S3)" 200 GET "$API/alertas" "" "$TK"
  req "catálogo de EPI" 200 GET "$API/catalogo/epis" "" "$TK"
  req "zonas cadastradas" 200 GET "$API/zonas" "" "$TK"
  req "logout" 200 POST "$API/auth/logout" "" "$TK"
fi
fim
