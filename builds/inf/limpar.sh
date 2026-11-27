#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build "inf" (todas as inferências) criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build (volumes mantidos)
#   ./limpar.sh --imagens          também as imagens da build (ods-<serviço>:<REF> do inf.env) e o
#                                  cache de build; imagem em uso por outra build não sai
#   ./limpar.sh --dados            também os volumes: registro do I3, saídas e
#                                  cache de OCR do I7 (pede para digitar "inf")
#   ./limpar.sh --codigo           também os clones que só esta build usa em SRC_DIR
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter <app>   mantém as imagens que <app> também usa
#
# NÃO toca no I1 (builds/i1, permanente), no vídeo de QR gerado em VIDEO_DIR, no container
# "kafka" da turma, nas imagens do SIS-1, em outras aplicações nem na pasta resultados/.
APP=inf
SEGREDOS=()

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
