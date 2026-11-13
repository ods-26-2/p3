#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build do A5 e posiciona cada um no commit
# fixado em a5.env. O ./a5.sh já roda isto; rode à mão só para baixar o código antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./a5.env
