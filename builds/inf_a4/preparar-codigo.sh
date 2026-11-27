#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build inf_a4 (I1, I2, I3) e posiciona cada um no
# commit fixado em inf_a4.env. O ./inf_a4.sh já roda isto; rode à mão só para baixar antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./inf_a4.env
