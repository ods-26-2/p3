#!/usr/bin/env bash
# Fluxo do A6 pela API do tradutor: estado, léxico, tradução português -> Libras (que publica
# o comando ao S6 da própria build). Não grava dados permanentes.
APP=a6
# shellcheck source=../validacao-geral/fluxo-comum.sh
source "$(dirname "$(readlink -f "$0")")/../validacao-geral/fluxo-comum.sh"
API=${API:-http://127.0.0.1:8086}

req "página do tradutor" 200 GET "$API/"
req "estado do tradutor" 200 GET "$API/api/state" && {
  confere "ligado ao Kafka" 'd["kafka_connected"] is True'
  confere "léxico carregado" 'd["lexicon_count"] > 0'
}
req "tradução português -> Libras" 200 POST "$API/api/translate" '{"text":"aluno conhecer banheiro","speed_factor":1.0}'
req "rota inexistente devolve 404" 404 POST "$API/api/zz-inexistente" '{}'
traj=$(docker exec ods-a6-s6-1 sh -c 'ls /trajetorias | wc -l' 2>/dev/null)
[[ "${traj:-0}" -gt 0 ]] && ok "S6 gravou $traj trajetória(s) na pasta compartilhada" || aviso "nenhuma trajetória do S6 na pasta compartilhada ainda"
fim
