#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build do A3 e posiciona cada um no commit
# fixado em a3.env. O ./a3.sh já roda isto; rode à mão só para baixar o código antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./a3.env
