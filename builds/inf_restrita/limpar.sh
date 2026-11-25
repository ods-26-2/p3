#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build "inf_restrita" (I1, I2, I3) criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build (volumes mantidos)
#   ./limpar.sh --imagens          também as imagens da build (ods-<serviço>:<REF> do .env) e o
#                                  cache de build. A ods-i1-gpu NÃO sai: é a mesma do I1 permanente
#                                  (builds/i1); imagem em uso por outra build também não sai
#   ./limpar.sh --dados            também o volume do registro do I3 (pede para digitar "inf_restrita")
#   ./limpar.sh --codigo           também os clones que só esta build usa em SRC_DIR
#   ./limpar.sh --tudo             as três opções acima
#   ./limpar.sh --imagens --manter <app>   mantém as imagens que <app> também usa
#
# NÃO toca nas engines (I1_ENGINES_DIR), nos vídeos (VIDEO_DIR), no I1 permanente (builds/i1), no
# container "kafka" da turma, nas imagens do SIS-1, em outras aplicações nem na pasta resultados/.
APP=inf_restrita
SEGREDOS=()

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
