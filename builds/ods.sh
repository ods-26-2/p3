#!/usr/bin/env bash
# ods.sh — orquestra as builds das aplicações ODS na Jetson (P3 / SIS-1).
#
# O cartão de 57 GB da Jetson não comporta todas as builds ao mesmo tempo. Este script
# mostra o que cada build ocupa e troca a aplicação ativa: remove as outras (containers
# e imagens, mantendo as imagens que a nova também usa) e sobe a nova.
#
#   ./ods.sh                       o mesmo que ./ods.sh lista
#   ./ods.sh lista                 cada build: containers, imagens presentes e espaço
#   ./ods.sh trocar <app>          remove as outras builds (--imagens) e sobe <app>
#   ./ods.sh trocar <app> --dados  idem, apagando também os volumes das outras (pede confirmação de cada uma)
#   ./ods.sh trocar <app> --codigo idem, apagando também os clones que só as outras usam
#   ./ods.sh subir <app> [--reconstruir]   só sobe <app> (= builds/<app>/<app>.sh subir)
#   ./ods.sh status <app>          = builds/<app>/<app>.sh status
#   ./ods.sh parar <app>           = builds/<app>/<app>.sh parar
#   ./ods.sh limpar <app> [opções] = builds/<app>/limpar.sh [opções]
#   ./ods.sh limpar-todas [opções] limpar.sh de todas as builds (ex.: --imagens)
#
# Nunca toca no container "kafka" da turma, nas imagens do SIS-1 nem em projetos que não
# sejam ods-<app> (ex.: os containers a1-db-1 e a1-kafka-1 de outro grupo).
set -euo pipefail

SCRIPT=$(readlink -f "$0")
DIR=$(dirname "$SCRIPT")
cd "$DIR"

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else V=; A=; R=; N=; fi
ok()    { echo "${V}✔${N} $*"; }
aviso() { echo "${A}!${N} $*"; }
erro()  { echo "${R}✘ $*${N}" >&2; exit 1; }

ajuda() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$SCRIPT"; }

apps() { local d; for d in "$DIR"/a[0-9]*/; do d=${d%/}; d=${d##*/}; [[ -f "$DIR/$d/$d.env" ]] && echo "$d"; done; }

checar_app() {
  [[ -n "${1:-}" ]] || erro "informe a aplicação (ex.: a5). Disponíveis: $(apps | tr '\n' ' ')"
  [[ -x "$DIR/$1/$1.sh" ]] || erro "não há build executável em $DIR/$1 ($1.sh)"
}

# Imagens que a build usa, uma por linha (sem precisar do .secrets.env).
imagens_de() {
  local app=$1
  ( cd "$DIR/$app"
    sec="$app.secrets.env"
    if [[ ! -f "$sec" ]]; then
      sec=$(mktemp); trap 'rm -f "$sec"' EXIT
      grep -oE '^[A-Z0-9_]+=' "$app.secrets.env.exemplo" 2>/dev/null | sed 's/=$/=nao-definido/' >"$sec" || true
    fi
    perfis=()
    while read -r p; do [[ -n "$p" ]] && perfis+=(--profile "$p"); done \
      < <(docker compose --env-file "$app.env" --env-file "$sec" config --profiles 2>/dev/null)
    docker compose --env-file "$app.env" --env-file "$sec" "${perfis[@]}" config --images 2>/dev/null | sort -u
  )
}

containers_de() { docker ps -aq --filter "label=com.docker.compose.project=ods-$1"; }
rodando_de()    { docker ps -q  --filter "label=com.docker.compose.project=ods-$1"; }

# Imagens da build presentes na placa (só as ods-*, que são as que a build constrói).
imagens_presentes() {
  local img
  while read -r img; do
    [[ "$img" == ods-* ]] && docker image inspect "$img" >/dev/null 2>&1 && echo "$img"
  done < <(imagens_de "$1")
  return 0
}

tamanho_mb() {   # soma do tamanho das imagens (sem descontar camadas compartilhadas)
  local total=0 s img
  for img in "$@"; do
    s=$(docker image inspect --format '{{.Size}}' "$img" 2>/dev/null || echo 0)
    total=$((total + s))
  done
  echo $((total / 1024 / 1024))
}

presente() { [[ -n "$(containers_de "$1")" || -n "$(imagens_presentes "$1")" ]]; }

lista() {
  command -v docker >/dev/null || erro "docker não encontrado"
  printf '%-5s %-12s %-10s %s\n' APP CONTAINERS RODANDO "IMAGENS DA BUILD (ods-*)"
  local app imgs
  for app in $(apps); do
    mapfile -t imgs < <(imagens_presentes "$app")
    printf '%-5s %-12s %-10s %s\n' "$app" "$(containers_de "$app" | wc -l)" "$(rodando_de "$app" | wc -l)" \
      "${#imgs[@]} imagens, ~$(tamanho_mb "${imgs[@]}") MB"
  done
  echo
  df -h / | tail -1 | awk '{print "Disco: " $4 " livres de " $2 " (" $5 " usado)"}'
  docker ps -a --filter name='^kafka$' --format 'Kafka da turma: {{.Status}}'
  return 0
}

trocar() {
  local nova=$1; shift
  checar_app "$nova"
  local extras=() o
  for o in "$@"; do
    case "$o" in
      --dados|--codigo) extras+=("$o") ;;
      *) erro "opção desconhecida para trocar: $o (use --dados ou --codigo)" ;;
    esac
  done

  echo "== Removendo as outras builds (mantendo as imagens que o $nova usa)"
  local app removidas=0
  for app in $(apps); do
    [[ "$app" == "$nova" ]] && continue
    presente "$app" || continue
    echo
    echo "-- $app"
    "$DIR/$app/limpar.sh" --imagens --manter "$nova" "${extras[@]}"
    removidas=$((removidas + 1))
  done
  (( removidas )) || ok "nenhuma outra build ocupa a placa"

  echo
  echo "== Subindo o $nova"
  exec "$DIR/$nova/$nova.sh" subir
}

case "${1:-lista}" in
  lista)  lista ;;
  trocar) shift; trocar "$@" ;;
  subir|status|parar)
    cmd=$1; checar_app "${2:-}"; app=$2; shift 2
    exec "$DIR/$app/$app.sh" "$cmd" "$@" ;;
  limpar)
    checar_app "${2:-}"; app=$2; shift 2
    exec "$DIR/$app/limpar.sh" "$@" ;;
  limpar-todas)
    shift
    for app in $(apps); do echo; echo "-- $app"; "$DIR/$app/limpar.sh" "$@"; done ;;
  -h|--help|ajuda) ajuda ;;
  *) erro "comando desconhecido: $1 (veja ./ods.sh --help)" ;;
esac
