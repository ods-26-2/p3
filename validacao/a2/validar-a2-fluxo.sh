#!/usr/bin/env bash
# Fluxo do A2 pela API de registros (8001) e pelo gerador de crachás (8082). Só leitura e
# validação de entrada; a decisão de acesso é testada pelo Kafka (builds/a2/a2.sh testar).
APP=a2
# shellcheck source=../validacao-geral/fluxo-comum.sh
source "$(dirname "$(readlink -f "$0")")/../validacao-geral/fluxo-comum.sh"
API=${API:-http://127.0.0.1:8001}; CRACHA=${CRACHA:-http://127.0.0.1:8082}

req "saúde da API de registros" 200 GET "$API/health"
req "registros de acesso" 200 GET "$API/acessos?limit=5"
req "filtro inválido recusado (direction)" 400 GET "$API/acessos?direction=zz-invalida"
req "registro inexistente devolve 404" 404 GET "$API/acessos/999999999"
req "página de visualização" 200 GET "$API/visualizar"
req "gerador de crachás" 200 GET "$CRACHA/" || req "gerador de crachás (redirecionamento)" 307 GET "$CRACHA/"
aviso "o gerador de crachás usa a chave AES fixa do código e guarda o banco dentro da imagem (pendência VER-2)"
fim
