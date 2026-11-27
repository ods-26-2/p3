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
#                                  (<app> = a1 … a8, inf: todas as inferências, ou
#                                  inf_a4: só I1, I2 e I3 para o A4, com I1 próprio no Kafka da nuvem,
#                                  inf_a8: I7 contínuo para o A8, no Kafka da nuvem)
#                                  (a build permanente do I1 fica de pé e com a imagem)
#                                  "trocar inf" mantém e sobe antes a inf_a4: a inf usa o I1 e o
#                                  I2 dela (27/11/2026)
#                                  inf_a4 e inf_a8 atendem as aplicações da NUVEM e convivem: trocar
#                                  para uma delas (ou para a inf) não derruba a outra. Trocar para
#                                  uma aplicação (a1 … a8) derruba as duas
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

apps() { local d; for d in "$DIR"/a[0-9]*/ "$DIR"/inf/ "$DIR"/inf_a4/ "$DIR"/inf_a8/; do d=${d%/}; d=${d##*/}; [[ -f "$DIR/$d/$d.env" ]] && echo "$d"; done; }
# Serviços permanentes (ex.: i1): aparecem na lista, mas o "trocar" não os remove.
permanentes() { local d; for d in i1; do [[ -f "$DIR/$d/$d.env" ]] && echo "$d"; done; return 0; }

# Build sobre a qual outra roda: o "trocar" não a remove e a sobe antes (a inf usa o I1 e o I2 da
# inf_a4 desde 27/11/2026).
base_de() { case "$1" in inf) echo inf_a4 ;; esac; return 0; }
# Builds que servem as aplicações da nuvem (27/11/2026): ficam de pé quando a troca é para uma
# delas ou para a inf (a A4 e a A8 da nuvem não perdem as inferências).
NUVEM=(inf_a4 inf_a8)
convivem_com() {   # convivem_com <app>: builds que o "trocar <app>" não remove (fora a própria)
  local n
  case "$1" in
    inf|inf_a4|inf_a8) for n in "${NUVEM[@]}"; do [[ "$n" != "$1" ]] && echo "$n"; done ;;
  esac
  return 0
}
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
  for app in $(apps) $(permanentes); do
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

  local base; base=$(base_de "$nova")
  local -A fica=(["$nova"]=1)
  [[ -n "$base" ]] && fica[$base]=1
  local c
  for c in $(convivem_com "$nova"); do fica[$c]=1; done
  local manter=() app
  for app in "${!fica[@]}"; do manter+=(--manter "$app"); done
  echo "== Removendo as outras builds (ficam: ${!fica[*]})"
  for c in "${NUVEM[@]}"; do
    if [[ -z "${fica[$c]:-}" ]] && presente "$c"; then
      aviso "a $c (aplicação da nuvem) também sai: o A${c#inf_a} da nuvem fica sem as inferências da placa"
    fi
  done
  local removidas=0
  for app in $(apps); do
    [[ -n "${fica[$app]:-}" ]] && continue
    presente "$app" || continue
    echo
    echo "-- $app"
    "$DIR/$app/limpar.sh" --imagens "${manter[@]}" "${extras[@]}"
    removidas=$((removidas + 1))
  done
  (( removidas )) || ok "nenhuma outra build ocupa a placa"

  if [[ -n "$base" ]]; then
    echo
    echo "== Subindo a base do $nova: $base (o que já está de pé não é reconstruído)"
    "$DIR/$base/$base.sh" subir
  fi

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
