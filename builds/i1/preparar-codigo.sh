#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build do I1 e posiciona cada um no commit fixado em
# i1.env. O ./i1.sh já roda isto; rode à mão só para baixar o código antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./i1.env
