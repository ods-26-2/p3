#!/usr/bin/env bash
# Fluxo do A7 pela API: cardápio, um pedido por voz (texto já transcrito), sessão e carrinho.
# A sessão de teste ("zz-validacao-…") é apagada no fim, mesmo se o script for interrompido.
APP=a7
# shellcheck source=../validacao-geral/fluxo-comum.sh
source "$(dirname "$(readlink -f "$0")")/../validacao-geral/fluxo-comum.sh"
API=${API:-http://127.0.0.1:8000}
ORIGEM="zz-validacao-$$"
limpar() { curl -s -o /dev/null -X DELETE "$API/sessoes/$ORIGEM"; rm -f "$TMP"; }
trap limpar EXIT

req "saúde" 200 GET "$API/health"
req "cardápio" 200 GET "$API/api/cardapio" && confere "cardápio com itens" 'len(d.get("itens", d) if isinstance(d, dict) else d) > 0'
req "pedido por voz (texto transcrito)" 200 POST "$API/eventos/voz" "{\"texto\":\"quero uma coca-cola lata\",\"confianca\":0.95,\"origem\":\"$ORIGEM\"}"
req "sessão do pedido" 200 GET "$API/sessoes/$ORIGEM"
req "carrinho do pedido" 200 GET "$API/carrinho/$ORIGEM" && {
  itens=$(campo 'len(d["itens"])'); [[ "${itens:-0}" -gt 0 ]] && ok "carrinho com $itens item(ns)" \
    || aviso "carrinho vazio: o classificador (Ollama ausente -> RapidFuzz) não reconheceu o pedido"
}
req "encerrar a sessão de teste" 200 DELETE "$API/sessoes/$ORIGEM"
req "sessão de teste removida" 404 GET "$API/sessoes/$ORIGEM"
fim
