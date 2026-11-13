#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build do A6 criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build; volumes ficam
#   ./limpar.sh --imagens          também as imagens da build e o cache de build
#   ./limpar.sh --dados            também os volumes (trajetórias geradas pelo S6);
#                                  pede que você digite "a6" para confirmar
#   ./limpar.sh --codigo           também os clones em SRC_DIR que nenhuma outra build usa
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter a8   não remove as imagens que a build do a8 também usa
#
# Nunca toca no container "kafka" da turma, nas imagens do SIS-1, em outras aplicações
# nem na pasta resultados/ (evidência dos testes).
APP=a6
SEGREDOS=()

lembrete_backup() {
  echo "  As trajetórias do S6 são regeneráveis; não há banco nesta build."
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
