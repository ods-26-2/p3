#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build inf e posiciona cada um no commit fixado em
# inf.env. O ./inf.sh já roda isto; rode à mão só para baixar o código antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./inf.env
