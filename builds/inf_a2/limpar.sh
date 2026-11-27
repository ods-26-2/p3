#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build "inf_a2" (I6 contínuo para o A2) criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build
#   ./limpar.sh --imagens          também a imagem da build (ods-i6:<I6_REF>) e o cache de build;
#                                  imagem em uso por outra build não sai (a build inf usa a mesma:
#                                  ./limpar.sh --imagens --manter inf)
#   ./limpar.sh --dados            também os volumes da build (não há volume; pede para digitar "inf_a2")
#   ./limpar.sh --codigo           também os clones que só esta build usa em SRC_DIR
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter <app>   mantém as imagens que <app> também usa
#
# NÃO apaga o vídeo do QR (VIDEO_DIR/a2-qr.mp4 e .codigo; é do P3, refeito pelo inf_a2.sh), o
# container "kafka" da turma, as imagens do SIS-1, outras builds nem a pasta resultados/.
APP=inf_a2
SEGREDOS=()

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
