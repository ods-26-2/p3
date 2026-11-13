#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build do A2 criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build; volumes ficam
#   ./limpar.sh --imagens          também as imagens da build e o cache de build
#   ./limpar.sh --dados            também os volumes (registro de acessos do A2, clipes do S4);
#                                  pede que você digite "a2" para confirmar
#   ./limpar.sh --codigo           também os clones em SRC_DIR que nenhuma outra build usa
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter a8   não remove as imagens que a build do a8 também usa
#
# Nunca toca no container "kafka" da turma, nas imagens do SIS-1, em outras aplicações
# nem na pasta resultados/ (evidência dos testes).
APP=a2
SEGREDOS=(A2_AES_KEY)

lembrete_backup() {
  echo "  Backup do registro de acessos antes de apagar:"
  echo "    docker compose --env-file a2.env --env-file a2.secrets.env cp a2:/app/data ./a2-backup-\$(date +%F)"
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
