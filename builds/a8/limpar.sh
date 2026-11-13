#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build do A8 criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build; volumes ficam
#   ./limpar.sh --imagens          também as imagens da build (ods-*, mysql:8.4…) e o cache de build
#   ./limpar.sh --dados            também os volumes (banco do A8, clipes do S4, métricas, cache do I7);
#                                  pede que você digite "a8" para confirmar
#   ./limpar.sh --codigo           também os clones em SRC_DIR que nenhuma outra build usa
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter a5   não remove as imagens que a build do a5 também usa
#
# Nunca toca no container "kafka" da turma, nas imagens do SIS-1, em outras aplicações
# nem na pasta resultados/ (evidência dos testes).
APP=a8
SEGREDOS=(A8_DB_PASSWORD A8_JWT_SECRET)

lembrete_backup() {
  echo "  Backup do banco antes de apagar:"
  echo "    docker compose --env-file a8.env --env-file a8.secrets.env exec -T a8-mysql \\"
  echo "      sh -c 'mysqldump -uroot -p\"\$MYSQL_ROOT_PASSWORD\" a8' > a8-backup-\$(date +%F).sql"
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
