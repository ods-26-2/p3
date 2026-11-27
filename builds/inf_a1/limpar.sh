#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build "inf_a1" (I8 contínuo para o A1) criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build
#   ./limpar.sh --imagens          também a imagem da build (ods-i8-publisher:<I8_REF>) e o cache de build;
#                                  imagem em uso por outra build não sai (a build inf e a do A1 usam a mesma:
#                                  ./limpar.sh --imagens --manter inf)
#   ./limpar.sh --dados            também os volumes da build (não há volume; pede para digitar "inf_a1")
#   ./limpar.sh --codigo           também os clones que só esta build usa em SRC_DIR
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter <app>   mantém as imagens que <app> também usa
#
# NÃO toca no container "kafka" da turma, nas imagens do SIS-1, em outras builds nem na pasta resultados/.
APP=inf_a1
SEGREDOS=()

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
