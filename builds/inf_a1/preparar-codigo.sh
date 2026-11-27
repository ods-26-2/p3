#!/usr/bin/env bash
# Clona (ou atualiza) o repositório da build inf_a1 (i8 e a1, só a taxonomia) e o posiciona no commit fixado em
# inf_a1.env. O ./inf_a1.sh já roda isto; rode à mão só para baixar o código antes.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
exec ../comum/preparar-codigo.sh ./inf_a1.env
