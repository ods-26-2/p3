#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build do A8 e posiciona cada um
# no commit fixado em a8.env. Rode antes de "docker compose build".
set -euo pipefail
cd "$(dirname "$0")"

set -a; source ./a8.env; set +a

declare -A REFS=(
  [a8]="$A8_REF" [i7]="$I7_REF"
  [p4]="$P4_REF" [i1]="$I1_REF" [i2]="$I2_REF" [i3]="$I3_REF"
  [s1]="$S1_REF" [s4]="$S4_REF" [s5]="$S5_REF"
  [b4]="$B4_REF"
)

mkdir -p "$SRC_DIR"
for repo in "${!REFS[@]}"; do
  ref="${REFS[$repo]}"
  dir="$SRC_DIR/$repo"
  if [ ! -d "$dir/.git" ]; then
    git clone --quiet "https://github.com/ods-26-2/$repo" "$dir"
  fi
  git -C "$dir" fetch --quiet origin
  git -C "$dir" checkout --quiet --detach "$ref"
  echo "$repo -> $(git -C "$dir" log -1 --format='%h %cs %s')"
done
