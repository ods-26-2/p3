#!/usr/bin/env bash
# guardar-no-notebook.sh — RODA NO NOTEBOOK (não na Jetson). Traz da Jetson para cá, comprimidas, as
# imagens da build inf_a4 e as engines TensorRT do I1 (P3 / SIS-1).
#
#   ./guardar-no-notebook.sh                  cria ~/ods-imagens/inf_a4-AAAAMMDD-HHMM/
#   ./guardar-no-notebook.sh --sem-engines    só as imagens
#
# Nada é gravado no disco da placa: o "docker save" sai pelo ssh e é comprimido aqui (zstd).
# Uma senha só: as chamadas ao ssh dividem uma conexão.
#
# A pasta criada tem:
#   imagens.tar.zst   docker save de ods-i1-gpu, ods-i2 e ods-i3 nos commits do inf_a4.env
#   engines.tar.zst   pastas das engines de I1_PACOTES (compiladas nesta placa; ~7 min cada a menos)
#   manifesto.txt     commits, imagens (id e tamanho), tamanho descomprimido, origem
#   inf_a4.env        cópia do .env usado
#   SHA256SUMS        para conferir a cópia (sha256sum -c)
#
# Para subir de volta na placa: ./subir-do-notebook.sh [pasta]
#
# Variáveis: JETSON (padrão ods@172.18.4.56), P3_JETSON (padrão /opt/ods/p3),
#            DESTINO (padrão ~/ods-imagens), ZSTD_NIVEL (padrão 3)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

JETSON=${JETSON:-ods@172.18.4.56}
P3_JETSON=${P3_JETSON:-/opt/ods/p3}
DESTINO=${DESTINO:-$HOME/ods-imagens}
NIVEL=${ZSTD_NIVEL:-3}
COM_ENGINES=1
case "${1:-}" in
  "") ;;
  --sem-engines) COM_ENGINES=0 ;;
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
  *) echo "opção desconhecida: $1 (use --sem-engines ou --help)" >&2; exit 1 ;;
esac

V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
ok()    { echo "${V}✔${N} $*"; }
aviso() { echo "${A}!${N} $*"; }
erro()  { echo "${R}✘ $*${N}" >&2; exit 1; }
etapa() { echo; echo "== $*"; }

for c in ssh zstd tar sha256sum; do command -v "$c" >/dev/null || erro "falta '$c' neste computador"; done
[[ "$(uname -n)" != ods-pc ]] || erro "este script roda no NOTEBOOK, não na Jetson"

set -a
# shellcheck source=inf_a4.env
source ./inf_a4.env
set +a
IMAGENS=("ods-i1-gpu:$I1_REF" "ods-i2:$I2_REF" "ods-i3:$I3_REF")
# Pasta de cada pacote de engine: app-plates/1.0.0 → app-plates-1.0.0 (como no inf_a4.sh)
ENGINES=()
for p in $I1_PACOTES; do ENGINES+=("${p/\//-}"); done

# Uma conexão ssh para todas as chamadas (uma senha só)
CTL=$(mktemp -d)
trap 'ssh -o ControlPath="$CTL/s" -O exit "$JETSON" 2>/dev/null || true; rm -rf "$CTL"' EXIT
SSH=(ssh -o ControlMaster=auto -o ControlPath="$CTL/s" -o ControlPersist=15m "$JETSON")

etapa "Conferindo a Jetson ($JETSON)"
"${SSH[@]}" true || erro "não consegui entrar em $JETSON por ssh"
ok "ssh em $JETSON"

# Os commits do .env da placa têm de ser os daqui: as tags das imagens são os commits.
env_placa=$("${SSH[@]}" "cat '$P3_JETSON/builds/inf_a4/inf_a4.env'" 2>/dev/null) \
  || erro "não achei $P3_JETSON/builds/inf_a4/inf_a4.env na placa (faltou o git pull no p3 da placa?)"
for r in I1_REF I2_REF I3_REF; do
  na_placa=$(sed -n "s/^$r=//p" <<<"$env_placa")
  [[ "$na_placa" == "${!r}" ]] || erro "$r difere: aqui ${!r:0:7}, na placa ${na_placa:0:7}. Deixe os dois p3 no mesmo commit (git pull)."
done
ok "commits iguais aos da placa: I1 ${I1_REF:0:7} · I2 ${I2_REF:0:7} · I3 ${I3_REF:0:7}"

declare -A ID=() TAM=()
total=0
for img in "${IMAGENS[@]}"; do
  info=$("${SSH[@]}" "docker image inspect --format '{{.Id}} {{.Size}}' '$img'" 2>/dev/null) \
    || erro "a imagem $img não existe na placa. Suba a build lá antes (./inf_a4.sh)."
  read -r id tam <<<"$info"
  ID[$img]=$id; TAM[$img]=$tam
  total=$((total + tam))
  ok "$img ($((tam / 1024 / 1024)) MB)"
done

livre=$(df -B1 --output=avail "$(mkdir -p "$DESTINO" && echo "$DESTINO")" | tail -1 | tr -dc '0-9')
(( livre > total )) || aviso "só $((livre / 1024 / 1024 / 1024)) GB livres em $DESTINO; as imagens somam $((total / 1024 / 1024 / 1024)) GB antes de comprimir"

PASTA="$DESTINO/inf_a4-$(date +%Y%m%d-%H%M)"
[[ ! -e "$PASTA" ]] || erro "$PASTA já existe"
PARCIAL="$PASTA.parcial"
rm -rf "$PARCIAL"; mkdir -p "$PARCIAL"

etapa "Imagens: docker save na placa → zstd aqui (alguns minutos; a do I1 é a maior)"
"${SSH[@]}" "docker save ${IMAGENS[*]}" | zstd -T0 "-$NIVEL" -q -o "$PARCIAL/imagens.tar.zst" \
  || erro "a cópia das imagens falhou; nada foi guardado (apague $PARCIAL)"
ok "imagens.tar.zst: $(du -h "$PARCIAL/imagens.tar.zst" | cut -f1)"

etapa "Conferindo a cópia (lê o tar inteiro)"
# Só zstd e tar (o python3 do notebook pode ser um atalho do asdf sem versão nesta pasta).
# 1ª leitura: lista todo o tar (confere a integridade) e soma os tamanhos (estimativa do disco).
bytes=$(zstd -dc "$PARCIAL/imagens.tar.zst" | tar -tvf - | awk '{ s += $3 } END { printf "%.0f", s }') \
  || erro "o tar das imagens está corrompido"
# 2ª leitura: as tags do manifest.json do docker save
tags=$(zstd -dc "$PARCIAL/imagens.tar.zst" | tar -xOf - manifest.json | grep -oE '"RepoTags": *\[[^]]*\]' \
  | grep -oE '"[^"]+:[^"]+"' | tr -d '"' | sort | tr '\n' ' ' | sed 's/ $//') \
  || erro "o tar das imagens não tem manifest.json"
[[ "$tags" == "$(printf '%s\n' "${IMAGENS[@]}" | sort | tr '\n' ' ' | sed 's/ $//')" ]] \
  || erro "o tar tem as tags '$tags', esperava ${IMAGENS[*]}"
ok "tar íntegro: ${#IMAGENS[@]} imagens, $((bytes / 1024 / 1024)) MB descomprimido"

engines_ok=()
if (( COM_ENGINES )); then
  etapa "Engines do I1 ($I1_ENGINES_DIR na placa)"
  # As pastas das engines podem ser só do root: lê por um container (a imagem do I3 já tem tar).
  LER=(docker run --rm --network none --entrypoint sh -v "$I1_ENGINES_DIR:/e:ro" "ods-i3:$I3_REF")
  existentes=$("${SSH[@]}" "${LER[*]} -c 'cd /e && ls -1d */ 2>/dev/null'" | tr -d '/' || true)
  for e in "${ENGINES[@]}"; do
    if grep -qx "$e" <<<"$existentes"; then engines_ok+=("$e"); else aviso "engine $e não existe na placa (fica de fora)"; fi
  done
  if (( ${#engines_ok[@]} )); then
    "${SSH[@]}" "${LER[*]} -c 'tar -C /e -cf - ${engines_ok[*]}'" | zstd -T0 "-$NIVEL" -q -o "$PARCIAL/engines.tar.zst" \
      || erro "a cópia das engines falhou"
    zstd -dc "$PARCIAL/engines.tar.zst" | tar -tf - >/dev/null || erro "o tar das engines está corrompido"
    ok "engines.tar.zst: ${engines_ok[*]} ($(du -h "$PARCIAL/engines.tar.zst" | cut -f1))"
  else
    aviso "nenhuma engine para guardar: a placa compila na subida (~7 min cada)"
  fi
fi

etapa "Manifesto"
cp inf_a4.env "$PARCIAL/inf_a4.env"
{
  echo "# Build inf_a4 guardada pelo guardar-no-notebook.sh (P3 / SIS-1)"
  echo "DATA=$(date -Iseconds)"
  echo "JETSON=$JETSON"
  echo "P3_COMMIT_PLACA=$("${SSH[@]}" "git -C '$P3_JETSON' rev-parse HEAD" 2>/dev/null || echo '?')"
  echo "I1_REF=$I1_REF"
  echo "I2_REF=$I2_REF"
  echo "I3_REF=$I3_REF"
  echo "BYTES_DESCOMPRIMIDOS=$bytes"
  for img in "${IMAGENS[@]}"; do echo "IMAGEM=$img ${ID[$img]} ${TAM[$img]}"; done
  echo "ENGINES_DIR=$I1_ENGINES_DIR"
  echo "ENGINES=${engines_ok[*]}"
} > "$PARCIAL/manifesto.txt"
(cd "$PARCIAL" && sha256sum ./*.tar.zst manifesto.txt inf_a4.env > SHA256SUMS)
mv "$PARCIAL" "$PASTA"
ok "pasta pronta: $PASTA ($(du -sh "$PASTA" | cut -f1))"
echo
echo "Para subir de volta na placa: ./subir-do-notebook.sh $PASTA"
