#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build "inf_a8" (I7 contínuo para o A8) criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build (volumes mantidos)
#   ./limpar.sh --imagens          também a imagem da build (ods-i7-gpu:<I7_REF>) e o cache de build;
#                                  imagem em uso por outra build não sai (a build inf usa a mesma:
#                                  ./limpar.sh --imagens --manter inf)
#   ./limpar.sh --dados            também os volumes: saídas e cache de OCR do I7 (pede para digitar "inf_a8")
#   ./limpar.sh --codigo           também os clones que só esta build usa em SRC_DIR
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter <app>   mantém as imagens que <app> também usa
#
# NÃO toca na engine do I1 (ENGINES_DIR), nos vídeos da SIS-2, no container "kafka" da turma, nas
# imagens do SIS-1, em outras builds nem na pasta resultados/.
APP=inf_a8
SEGREDOS=()

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
