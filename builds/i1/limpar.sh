#!/usr/bin/env bash
# limpar.sh — remove da Jetson o que a build dedicada do I1 criou (P3 / SIS-1).
#
#   ./limpar.sh                    containers e rede da build (o I1 para de atender as aplicações)
#   ./limpar.sh --imagens          também a imagem ods-i1-gpu:<I1_REF> e o cache de build
#                                  (a imagem não sai se o A8 ou o A5 estiverem com um container dela)
#   ./limpar.sh --dados            a build não tem volumes; mantido pela regra comum
#   ./limpar.sh --codigo           também o clone do I1 e do B4 em SRC_DIR, se nenhuma outra build usar
#   ./limpar.sh --tudo             as três opções acima
#
# NÃO apaga as engines em I1_ENGINES_DIR (as mesmas do A8 e do A5; recompilar leva ~7 min cada).
# Para apagá-las, à mão: sudo rm -rf <I1_ENGINES_DIR>/<pacote>-<versão>
# Nunca toca no container "kafka" da turma, nas imagens do SIS-1, em outras aplicações
# nem na pasta resultados/ (evidência dos testes).
APP=i1
SEGREDOS=()

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
limpar_build "$@"
