#!/usr/bin/env bash
# builds/comum/preparar-codigo.sh <arquivo .env>
#
# Clona (ou atualiza) cada repositório citado no .env e o posiciona no commit fixado.
# Toda variável <REPO>_REF=<commit completo> vira o clone SRC_DIR/<repo> de
# https://github.com/ods-26-2/<repo> (ex.: S4_REF -> s4, B4_REF -> b4).
# O commit pode estar em qualquer branch (S4 usa master; A2, A3, I6 e S2 têm o código
# mais novo fora da main): o "fetch" traz todas as branches.
#
# Recusa ref que não seja um commit completo (40 caracteres): nada de main ou latest.
set -euo pipefail

ENV_ARQ=${1:?uso: preparar-codigo.sh <arquivo .env>}
[[ -f "$ENV_ARQ" ]] || { echo "não encontrado: $ENV_ARQ" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
source "$ENV_ARQ"
set +a
: "${SRC_DIR:?defina SRC_DIR em $ENV_ARQ}"

mkdir -p "$SRC_DIR"
while IFS='=' read -r var ref; do
  repo=$(echo "${var%_REF}" | tr 'A-Z' 'a-z')
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || { echo "$var não é um commit completo: '$ref'" >&2; exit 1; }
  dir="$SRC_DIR/$repo"
  if [[ ! -d "$dir/.git" ]]; then
    git clone --quiet "https://github.com/ods-26-2/$repo" "$dir"
  fi
  if ! git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null; then
    git -C "$dir" fetch --quiet origin
  fi
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]]; then
    echo "$dir tem alterações locais; não mexo. Confira com: git -C $dir status" >&2
    exit 1
  fi
  git -C "$dir" checkout --quiet --detach "$ref"
  echo "$repo -> $(git -C "$dir" log -1 --format='%h %cs %s')"
done < <(grep -E '^[A-Z0-9]+_REF=' "$ENV_ARQ")
