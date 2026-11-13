#!/usr/bin/env bash
# Clona (ou atualiza) os repositórios da build do A8 e posiciona cada um no commit fixado em
# a8.env. Idempotente: com o commit já presente no clone, não acessa a rede.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

set -a; source ./a8.env; set +a

declare -A REFS=(
  [a8]="$A8_REF" [i7]="$I7_REF"
  [p4]="$P4_REF" [i1]="$I1_REF" [i2]="$I2_REF" [i3]="$I3_REF"
  [s1]="$S1_REF" [s4]="$S4_REF" [s5]="$S5_REF"
  [b4]="$B4_REF"
)

mkdir -p "$SRC_DIR" 2>/dev/null || {
  echo "não consigo criar $SRC_DIR. Uma vez só: sudo mkdir -p $SRC_DIR && sudo chown $(id -un):docker $SRC_DIR" >&2
  exit 1
}
for repo in "${!REFS[@]}"; do
  ref="${REFS[$repo]}"
  dir="$SRC_DIR/$repo"
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || { echo "${repo^^}_REF não é um commit completo: '$ref'" >&2; exit 1; }
  if [[ -e "$dir" && ! -d "$dir/.git" ]]; then
    echo "$dir existe mas não é um clone (clone interrompido?). Apague e rode de novo: rm -rf $dir" >&2
    exit 1
  fi
  if [[ ! -d "$dir/.git" ]]; then
    git clone --quiet "https://github.com/ods-26-2/$repo" "$dir"
  fi
  # Só vai à rede se o commit ainda não estiver no clone.
  if ! git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null; then
    git -C "$dir" fetch --quiet origin
  fi
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]]; then
    echo "$dir tem alterações locais; não mexo. Confira com: git -C $dir status" >&2
    exit 1
  fi
  if [[ "$(git -C "$dir" rev-parse HEAD)" != "$ref" ]]; then
    git -C "$dir" checkout --quiet --detach "$ref"
  fi
  echo "$repo -> $(git -C "$dir" log -1 --format='%h %cs %s')"
done
