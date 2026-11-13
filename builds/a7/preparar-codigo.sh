#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build do A7 e posiciona cada um no commit
# fixado em a7.env. O ./a7.sh já roda isto; rode à mão só para baixar o código antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./a7.env
