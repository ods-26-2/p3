#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build do A1 criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build; volumes ficam
#   ./limpar.sh --imagens          também as imagens da build e o cache de build
#   ./limpar.sh --dados            também os volumes (banco do A1, clipes do S4, métricas do S5);
#                                  pede que você digite "a1" para confirmar
#   ./limpar.sh --codigo           também os clones em SRC_DIR que nenhuma outra build usa
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter a8   não remove as imagens que a build do a8 também usa
#
# Nunca toca no container "kafka" da turma, nas imagens do SIS-1, em outras aplicações
# nem na pasta resultados/ (evidência dos testes).
APP=a1
SEGREDOS=(A1_DB_PASSWORD)

lembrete_backup() {
  echo "  Backup do banco antes de apagar:"
  echo "    docker compose --env-file a1.env --env-file a1.secrets.env exec -T a1-db \\"
  echo "      pg_dump -U a1 a1 > a1-backup-\$(date +%F).sql"
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
