#!/usr/bin/env bash
# subir-do-notebook.sh — RODA NO NOTEBOOK (não na Jetson). Sobe a build inf_a4 na Jetson a partir da
# pasta criada pelo guardar-no-notebook.sh, sem construir imagem nenhuma (P3 / SIS-1).
#
#   ./subir-do-notebook.sh                    usa a pasta mais recente em ~/ods-imagens/inf_a4-*
#   ./subir-do-notebook.sh <pasta>
#   ./subir-do-notebook.sh <pasta> --sem-subir   só carrega imagens e engines (não roda o inf_a4.sh)
#   ./subir-do-notebook.sh --descomprimir-na-placa   manda comprimido e a placa descomprime (rede lenta,
#                                  ex.: de casa): zstd se a placa tiver; senão gzip (com nice 19)
#   JETSON=ods@200.17.66.56 ./subir-do-notebook.sh --descomprimir-na-placa    (de fora do laboratório)
#
# Passos: confere a pasta (SHA256SUMS), os commits do p3 da placa e o disco dela; manda para a placa
# só as imagens que faltam ("docker load" lendo pelo ssh, sem arquivo no disco da placa) e as engines
# que faltam; por fim roda ./inf_a4.sh subir lá (o que já existe não é reconstruído).
#
# Variáveis: JETSON (padrão ods@172.18.4.56), P3_JETSON (padrão /opt/ods/p3),
#            DESTINO (padrão ~/ods-imagens), MIN_LIVRE_GB (padrão 4), FORCAR=1 (ignora o disco)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

JETSON=${JETSON:-ods@172.18.4.56}
P3_JETSON=${P3_JETSON:-/opt/ods/p3}
DESTINO=${DESTINO:-$HOME/ods-imagens}
MIN_LIVRE_GB=${MIN_LIVRE_GB:-4}
PASTA="" SUBIR=1 NA_PLACA=0
for a in "$@"; do
  case "$a" in
    --sem-subir) SUBIR=0 ;;
    --descomprimir-na-placa) NA_PLACA=1 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*) echo "opção desconhecida: $a (use --sem-subir, --descomprimir-na-placa ou --help)" >&2; exit 1 ;;
    *) PASTA=$a ;;
  esac
done

V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
ok()    { echo "${V}✔${N} $*"; }
aviso() { echo "${A}!${N} $*"; }
erro()  { echo "${R}✘ $*${N}" >&2; exit 1; }
etapa() { echo; echo "== $*"; }

for c in ssh zstd sha256sum; do command -v "$c" >/dev/null || erro "falta '$c' neste computador"; done
[[ "$(uname -n)" != ods-pc ]] || erro "este script roda no NOTEBOOK, não na Jetson"

if [[ -z "$PASTA" ]]; then
  # shellcheck disable=SC2012
  PASTA=$(ls -1dt "$DESTINO"/inf_a4-*/ 2>/dev/null | grep -v '\.parcial/$' | head -1 || true)
  [[ -n "$PASTA" ]] || erro "nenhuma pasta inf_a4-* em $DESTINO (rode antes ./guardar-no-notebook.sh)"
fi
PASTA=$(readlink -f "$PASTA")
[[ -f "$PASTA/manifesto.txt" && -f "$PASTA/imagens.tar.zst" ]] || erro "$PASTA não é uma pasta do guardar-no-notebook.sh"
# A pasta tem de ser DESTA build (cada build tem o seu guardar/subir): o manifesto diz qual é
BUILD_PASTA=$(sed -n 's/^# Build \([^ ]*\) guardada.*/\1/p' "$PASTA/manifesto.txt" | head -1)
[[ "$BUILD_PASTA" == inf_a4 ]] || erro "a pasta $PASTA é da build '${BUILD_PASTA:-?}', não da inf_a4.
  Use o script da build dela: ../${BUILD_PASTA:-<build>}/subir-do-notebook.sh $PASTA"

etapa "Conferindo a pasta $PASTA"
(cd "$PASTA" && sha256sum -c --quiet SHA256SUMS) || erro "a pasta está corrompida (SHA256SUMS não confere)"
ok "SHA256SUMS confere"
campo() { sed -n "s/^$1=//p" "$PASTA/manifesto.txt" | head -1; }
I1_REF=$(campo I1_REF); I2_REF=$(campo I2_REF); I3_REF=$(campo I3_REF)
BYTES=$(campo BYTES_DESCOMPRIMIDOS); ENGINES_DIR=$(campo ENGINES_DIR); ENGINES=$(campo ENGINES)
declare -A ID=()
IMAGENS=()
while read -r img id _; do IMAGENS+=("$img"); ID[$img]=$id; done < <(sed -n 's/^IMAGEM=//p' "$PASTA/manifesto.txt")
echo "  guardada em $(campo DATA) · I1 ${I1_REF:0:7} · I2 ${I2_REF:0:7} · I3 ${I3_REF:0:7}"

CTL=$(mktemp -d)
trap 'ssh -o ControlPath="$CTL/s" -O exit "$JETSON" 2>/dev/null || true; rm -rf "$CTL"' EXIT
SSH=(ssh -o ControlMaster=auto -o ControlPath="$CTL/s" -o ControlPersist=30m "$JETSON")

etapa "Conferindo a Jetson ($JETSON)"
"${SSH[@]}" true || erro "não consegui entrar em $JETSON por ssh"
ok "ssh em $JETSON"

# Descompressor da placa (--descomprimir-na-placa): zstd, senão pigz/gzip. Vazio = descomprime aqui.
COMP=""
if (( NA_PLACA )); then
  COMP=$("${SSH[@]}" 'for c in zstd pigz gzip; do command -v $c >/dev/null && { echo $c; break; }; done' || true)
  [[ -n "$COMP" ]] || erro "a placa não tem zstd, pigz nem gzip; rode sem --descomprimir-na-placa"
  [[ "$COMP" == zstd ]] || command -v gzip >/dev/null || erro "falta 'gzip' neste computador (a placa só tem $COMP)"
  ok "descompressão na placa: $COMP (nice 19)"
fi

# enviar <arquivo.zst> '<comando na placa que lê um tar do stdin>'
# O comando roda num bash com pipefail na placa. Não use aspas simples dentro dele.
enviar() {
  case "$COMP" in
    "")   zstd -dc "$1" | "${SSH[@]}" "bash -o pipefail -c '$2'" ;;
    zstd) "${SSH[@]}" "bash -o pipefail -c 'nice -n 19 zstd -dc | $2'" < "$1" ;;
    *)    zstd -dc "$1" | gzip -1 -c | "${SSH[@]}" "bash -o pipefail -c 'nice -n 19 $COMP -dc | $2'" ;;
  esac
}

env_placa=$("${SSH[@]}" "cat '$P3_JETSON/builds/inf_a4/inf_a4.env'" 2>/dev/null) \
  || erro "não achei $P3_JETSON/builds/inf_a4/inf_a4.env na placa (faltou o git pull no p3 da placa?)"
for r in I1_REF I2_REF I3_REF; do
  na_placa=$(sed -n "s/^$r=//p" <<<"$env_placa")
  # Commits diferentes: o inf_a4.sh não acharia as tags e reconstruiria tudo na placa
  [[ "$na_placa" == "${!r}" ]] || erro "$r difere: na pasta ${!r:0:7}, na placa ${na_placa:0:7}. Use a pasta do mesmo commit ou ponha o p3 da placa no commit da pasta."
done
ok "commits do p3 da placa iguais aos da pasta"
"${SSH[@]}" "docker ps -a --filter name='^kafka\$' --format 'Kafka da turma na placa: {{.Status}}'" || true
"${SSH[@]}" "docker image inspect confluentinc/cp-kafka:latest >/dev/null 2>&1" \
  || aviso "a placa não tem confluentinc/cp-kafka:latest: o inf_a4.sh vai baixá-la (~1 GB)"

faltam=()
for img in "${IMAGENS[@]}"; do
  id=$("${SSH[@]}" "docker image inspect --format '{{.Id}}' '$img' 2>/dev/null" || true)
  if [[ "$id" == "${ID[$img]}" ]]; then ok "já na placa: $img"
  elif [[ -n "$id" ]]; then aviso "na placa, $img tem outro id (${id:7:12}); a da pasta a substitui"; faltam+=("$img")
  else faltam+=("$img"); fi
done

livre_gb() { "${SSH[@]}" "df -BG --output=avail / | tail -1" | tr -dc '0-9'; }
echo "Disco da placa antes:"; "${SSH[@]}" "df -h /" | sed 's/^/  /'

if (( ${#faltam[@]} )); then
  etapa "Imagens: $([[ -n "$COMP" ]] && echo "rede → $COMP na placa" || echo "zstd aqui → rede") → docker load na placa (${faltam[*]})"
  precisa=$(( BYTES / 1024 / 1024 / 1024 + 1 + MIN_LIVRE_GB ))
  livre=$(livre_gb)
  # Estimativa por cima: o docker load pula as camadas que a placa já tem
  if (( livre < precisa )) && [[ "${FORCAR:-0}" != 1 ]]; then
    erro "a placa tem ${livre} GB livres; o tar tem até $((BYTES / 1024 / 1024 / 1024 + 1)) GB e o mínimo livre é ${MIN_LIVRE_GB} GB.
  Libere espaço (ex.: ../ods.sh trocar inf_a4 remove as outras builds) ou, se as camadas grandes já
  estão na placa (base TensorRT do I1), rode com FORCAR=1."
  fi
  enviar "$PASTA/imagens.tar.zst" "docker load" || erro "o docker load falhou na placa"
  for img in "${IMAGENS[@]}"; do
    id=$("${SSH[@]}" "docker image inspect --format '{{.Id}}' '$img' 2>/dev/null" || true)
    [[ "$id" == "${ID[$img]}" ]] || erro "depois do load, $img não tem o id esperado (${ID[$img]:7:12})"
  done
  ok "imagens carregadas e conferidas pelo id"
  (( $(livre_gb) >= MIN_LIVRE_GB )) || erro "a placa ficou com menos de ${MIN_LIVRE_GB} GB livres; não subo a build"
else
  ok "todas as imagens já estão na placa: nada a carregar"
fi

if [[ -f "$PASTA/engines.tar.zst" && -n "$ENGINES" ]]; then
  etapa "Engines do I1 ($ENGINES_DIR na placa)"
  "${SSH[@]}" "mkdir -p '$ENGINES_DIR'" 2>/dev/null \
    || aviso "não consegui criar $ENGINES_DIR como $JETSON; o Docker vai criá-la como root"
  # Pela imagem do I3 (tem tar), como root: as pastas das engines podem ser só do root.
  # --skip-old-files: engine que já existe na placa fica como está.
  enviar "$PASTA/engines.tar.zst" \
    "docker run --rm -i --network none --entrypoint tar -v $ENGINES_DIR:/e ods-i3:$I3_REF -C /e -xf - --skip-old-files" \
    || erro "não consegui gravar as engines na placa"
  ok "engines na placa: $ENGINES (o inf_a4.sh só recompila a que não carregar)"
fi

echo "Disco da placa depois:"; "${SSH[@]}" "df -h /" | sed 's/^/  /'

if (( SUBIR )); then
  etapa "Subindo a build na placa (./inf_a4.sh subir)"
  # -t: o inf_a4.sh pode pedir a senha do sudo para esvaziar o cache de páginas (memória da GPU)
  ssh -t "${SSH[@]:1}" "cd '$P3_JETSON/builds/inf_a4' && ./inf_a4.sh subir"
else
  echo
  echo "Para subir na placa: cd $P3_JETSON/builds/inf_a4 && ./inf_a4.sh"
fi
