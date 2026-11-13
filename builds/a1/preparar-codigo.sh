#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build do A1 e posiciona cada um no commit
# fixado em a1.env. O ./a1.sh já roda isto; rode à mão só para baixar o código antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./a1.env
