#!/usr/bin/env bash
# guardar-no-notebook.sh — RODA NO NOTEBOOK (não na Jetson). Traz da Jetson para cá, comprimidas, as
# imagens da build inf (I3, I6, I7, I8, I9) (P3 / SIS-1). Mesmo molde do ../inf_a4/guardar-no-notebook.sh.
#
#   ./guardar-no-notebook.sh                  cria ~/ods-imagens/inf-AAAAMMDD-HHMM/
#   ./guardar-no-notebook.sh --com-engine     também a engine app-plates-1.0.0 do I7 (a mesma do I1)
#   ./guardar-no-notebook.sh --comprimir-na-placa   comprime NA PLACA antes de mandar (rede lenta,
#                                             ex.: de casa): ~metade dos bytes pela rede, usando a CPU
#                                             da placa (com nice 19). zstd se a placa tiver; senão gzip
#   JETSON=ods@200.17.66.56 ./guardar-no-notebook.sh --comprimir-na-placa    (de fora do laboratório)
#
# Nada é gravado no disco da placa: o "docker save" sai pelo ssh e é comprimido no caminho (aqui,
# ou na placa com --comprimir-na-placa). A pasta guarda sempre .zst.
# Uma senha só: as chamadas ao ssh dividem uma conexão.
#
# A pasta criada tem:
#   imagens.tar.zst   docker save de ods-i3, ods-i6, ods-i7-gpu, ods-i8-publisher e ods-i9 nos
#                     commits do inf.env (o I1 e o I2 são da inf_a4: guarde-os com o script dela;
#                     o ods-i3 é a mesma imagem nas duas, e vai nas duas pastas)
#   engines.tar.zst   só com --com-engine: app-plates-1.0.0 (o ../inf_a4/guardar-no-notebook.sh já
#                     guarda todas as engines do I1, inclusive esta)
#   manifesto.txt     commits, imagens (id e tamanho), tamanho descomprimido, origem
#   inf.env           cópia do .env usado
#   SHA256SUMS        para conferir a cópia (sha256sum -c)
#
# Fica de fora: confluentinc/cp-kafka:latest (pública, o docker pull baixa) e o vídeo de QR
# (o ./inf.sh gera de novo em VIDEO_DIR).
#
# Para subir de volta na placa (sem script próprio ainda), na pasta criada:
#   zstd -dc imagens.tar.zst | ssh ods@172.18.4.56 docker load
#
# Variáveis: JETSON (padrão ods@172.18.4.56), P3_JETSON (padrão /opt/ods/p3),
#            DESTINO (padrão ~/ods-imagens), ZSTD_NIVEL (padrão 3)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

JETSON=${JETSON:-ods@172.18.4.56}
P3_JETSON=${P3_JETSON:-/opt/ods/p3}
DESTINO=${DESTINO:-$HOME/ods-imagens}
NIVEL=${ZSTD_NIVEL:-3}
COM_ENGINES=0 NA_PLACA=0
for a in "$@"; do
  case "$a" in
    --com-engine) COM_ENGINES=1 ;;
    --comprimir-na-placa) NA_PLACA=1 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $a (use --com-engine, --comprimir-na-placa ou --help)" >&2; exit 1 ;;
  esac
done

V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
ok()    { echo "${V}✔${N} $*"; }
aviso() { echo "${A}!${N} $*"; }
erro()  { echo "${R}✘ $*${N}" >&2; exit 1; }
etapa() { echo; echo "== $*"; }

for c in ssh zstd tar sha256sum; do command -v "$c" >/dev/null || erro "falta '$c' neste computador"; done
[[ "$(uname -n)" != ods-pc ]] || erro "este script roda no NOTEBOOK, não na Jetson"

set -a
# shellcheck source=inf.env
source ./inf.env
set +a
# As mesmas do docker-compose.yml (serviços ativos; o i6-gerar-video usa a do i6)
REFS=(I3_REF I6_REF I7_REF I8_REF I9_REF)
IMAGENS=("ods-i3:$I3_REF" "ods-i6:$I6_REF" "ods-i7-gpu:$I7_REF" "ods-i8-publisher:$I8_REF" "ods-i9:$I9_REF")
# Única engine que esta build lê (o I7, só leitura): a app-plates do I1
ENGINES=(app-plates-1.0.0)

# Uma conexão ssh para todas as chamadas (uma senha só)
CTL=$(mktemp -d)
trap 'ssh -o ControlPath="$CTL/s" -O exit "$JETSON" 2>/dev/null || true; rm -rf "$CTL"' EXIT
SSH=(ssh -o ControlMaster=auto -o ControlPath="$CTL/s" -o ControlPersist=15m "$JETSON")

etapa "Conferindo a Jetson ($JETSON)"
"${SSH[@]}" true || erro "não consegui entrar em $JETSON por ssh"
ok "ssh em $JETSON"

# Compressor da placa (--comprimir-na-placa): zstd, senão pigz/gzip. Vazio = comprime aqui.
COMP=""
if (( NA_PLACA )); then
  COMP=$("${SSH[@]}" 'for c in zstd pigz gzip; do command -v $c >/dev/null && { echo $c; break; }; done' || true)
  [[ -n "$COMP" ]] || erro "a placa não tem zstd, pigz nem gzip; rode sem --comprimir-na-placa"
  [[ "$COMP" == zstd ]] || command -v gzip >/dev/null || erro "falta 'gzip' neste computador (a placa só tem $COMP)"
  ok "compressão na placa: $COMP (nice 19); aqui o arquivo é gravado em zstd"
fi

# trazer '<comando na placa que escreve um tar no stdout>' <arquivo.zst>
# O comando roda num bash com pipefail na placa: falha do docker save não passa por sucesso.
# Não use aspas simples dentro do comando (ele vai entre aspas simples para o bash da placa).
trazer() {
  case "$COMP" in
    "")   "${SSH[@]}" "bash -o pipefail -c '$1'" | zstd -T0 "-$NIVEL" -q -o "$2" ;;
    zstd) "${SSH[@]}" "bash -o pipefail -c '$1 | nice -n 19 zstd -T0 -$NIVEL -q -c'" > "$2" ;;
    *)    "${SSH[@]}" "bash -o pipefail -c '$1 | nice -n 19 $COMP -1 -c'" | gzip -dc | zstd -T0 "-$NIVEL" -q -o "$2" ;;
  esac
}

# Os commits do .env da placa têm de ser os daqui: as tags das imagens são os commits.
env_placa=$("${SSH[@]}" "cat '$P3_JETSON/builds/inf/inf.env'" 2>/dev/null) \
  || erro "não achei $P3_JETSON/builds/inf/inf.env na placa (faltou o git pull no p3 da placa?)"
for r in "${REFS[@]}"; do
  na_placa=$(sed -n "s/^$r=//p" <<<"$env_placa")
  [[ "$na_placa" == "${!r}" ]] || erro "$r difere: aqui ${!r:0:7}, na placa ${na_placa:0:7}. Deixe os dois p3 no mesmo commit (git pull)."
done
ok "commits iguais aos da placa: I3 ${I3_REF:0:7} · I6 ${I6_REF:0:7} · I7 ${I7_REF:0:7} · I8 ${I8_REF:0:7} · I9 ${I9_REF:0:7}"

declare -A ID=() TAM=()
total=0
for img in "${IMAGENS[@]}"; do
  info=$("${SSH[@]}" "docker image inspect --format '{{.Id}} {{.Size}}' '$img'" 2>/dev/null) \
    || erro "a imagem $img não existe na placa. Suba a build lá antes (./inf.sh; o I7 e o I8 só são construídos no primeiro ./inf.sh testar ou ./inf.sh i7/i8)"
  read -r id tam <<<"$info"
  ID[$img]=$id; TAM[$img]=$tam
  total=$((total + tam))
  ok "$img ($((tam / 1024 / 1024)) MB)"
done

livre=$(df -B1 --output=avail "$(mkdir -p "$DESTINO" && echo "$DESTINO")" | tail -1 | tr -dc '0-9')
(( livre > total )) || aviso "só $((livre / 1024 / 1024 / 1024)) GB livres em $DESTINO; as imagens somam $((total / 1024 / 1024 / 1024)) GB antes de comprimir"

PASTA="$DESTINO/inf-$(date +%Y%m%d-%H%M)"
[[ ! -e "$PASTA" ]] || erro "$PASTA já existe"
PARCIAL="$PASTA.parcial"
rm -rf "$PARCIAL"; mkdir -p "$PARCIAL"

case "$COMP" in
  "") rota="rede → zstd aqui" ;; zstd) rota="zstd na placa → rede" ;; *) rota="$COMP na placa → rede → zstd aqui" ;;
esac
etapa "Imagens: docker save na placa → $rota (alguns minutos; a do I7 é a maior)"
trazer "docker save ${IMAGENS[*]}" "$PARCIAL/imagens.tar.zst" \
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
  etapa "Engine do I7 ($ENGINES_DIR na placa)"
  # As pastas das engines podem ser só do root: lê por um container (a imagem do I3 já tem tar).
  LER=(docker run --rm --network none --entrypoint sh -v "$ENGINES_DIR:/e:ro" "ods-i3:$I3_REF")
  existentes=$("${SSH[@]}" "${LER[*]} -c 'cd /e && ls -1d */ 2>/dev/null'" | tr -d '/' || true)
  for e in "${ENGINES[@]}"; do
    if grep -qx "$e" <<<"$existentes"; then engines_ok+=("$e"); else aviso "engine $e não existe na placa (fica de fora)"; fi
  done
  if (( ${#engines_ok[@]} )); then
    trazer "${LER[*]} -c \"tar -C /e -cf - ${engines_ok[*]}\"" "$PARCIAL/engines.tar.zst" \
      || erro "a cópia das engines falhou"
    zstd -dc "$PARCIAL/engines.tar.zst" | tar -tf - >/dev/null || erro "o tar das engines está corrompido"
    ok "engines.tar.zst: ${engines_ok[*]} ($(du -h "$PARCIAL/engines.tar.zst" | cut -f1))"
  else
    aviso "nenhuma engine para guardar: a inf_a4 compila a app-plates na subida dela (~7 min)"
  fi
fi

etapa "Manifesto"
cp inf.env "$PARCIAL/inf.env"
{
  echo "# Build inf guardada pelo guardar-no-notebook.sh (P3 / SIS-1)"
  echo "DATA=$(date -Iseconds)"
  echo "JETSON=$JETSON"
  echo "COMPRESSAO_NA_PLACA=${COMP:-não}"
  echo "P3_COMMIT_PLACA=$("${SSH[@]}" "git -C '$P3_JETSON' rev-parse HEAD" 2>/dev/null || echo '?')"
  for r in "${REFS[@]}"; do echo "$r=${!r}"; done
  echo "BYTES_DESCOMPRIMIDOS=$bytes"
  for img in "${IMAGENS[@]}"; do echo "IMAGEM=$img ${ID[$img]} ${TAM[$img]}"; done
  echo "ENGINES_DIR=$ENGINES_DIR"
  echo "ENGINES=${engines_ok[*]}"
} > "$PARCIAL/manifesto.txt"
(cd "$PARCIAL" && sha256sum ./*.tar.zst manifesto.txt inf.env > SHA256SUMS)
mv "$PARCIAL" "$PASTA"
ok "pasta pronta: $PASTA ($(du -sh "$PASTA" | cut -f1))"
echo
echo "Para carregar de volta na placa: zstd -dc $PASTA/imagens.tar.zst | ssh $JETSON docker load"
