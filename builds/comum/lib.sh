#!/usr/bin/env bash
# builds/comum/lib.sh — funções comuns das builds ODS (P3 / SIS-1).
#
# Não é executado sozinho: o <app>.sh e o limpar.sh de cada aplicação fazem "source" dele.
# Antes do source, o script da aplicação define:
#
#   APP=a3                       nome da aplicação (pasta builds/a3, a3.env, projeto ods-a3)
#   SEGREDOS=(A3_X A3_Y)         variáveis obrigatórias do <app>.secrets.env (pode ser vazio)
#   ETAPAS=("s4" "a3 s1 i2")     ordem de construção: grupos de serviços com "build:".
#                                As maiores por último e sozinhas (o disco da Jetson é pequeno).
#   ONESHOT=(kafka-topicos)      serviços do "up" que rodam uma vez e terminam (código 0)
#
# e, se quiser, as funções:
#   checar_entradas              confere arquivos de entrada (vídeo, imagens…); só avisa
#   pos_subida                   depois do "up": confere APIs e mostra os endereços
#   testar                       teste de aceitação da aplicação (sem ele, "testar" só avisa)
#
# Depois chama:  ods_principal "$@"     (no <app>.sh)
#          ou:   limpar_build "$@"      (no limpar.sh)
#
# Regras que este arquivo segue (CLAUDE.md, seção 4):
#   - nunca toca no container "kafka", nas imagens do SIS-1 (nvcr.io/nvidia/l4t-*, ods/base-gpu:*)
#     nem em recursos de outras aplicações;
#   - "docker builder prune -af" depois de cada etapa de build;
#   - para abaixo de MIN_LIVRE_GB livres;
#   - volumes só saem com --dados, e só depois de o usuário digitar o nome da aplicação;
#   - a pasta resultados/ (evidência) nunca é apagada.

set -euo pipefail

: "${APP:?defina APP antes de carregar comum/lib.sh}"
declare -p SEGREDOS >/dev/null 2>&1 || SEGREDOS=()
declare -p ETAPAS >/dev/null 2>&1 || ETAPAS=()
declare -p ONESHOT >/dev/null 2>&1 || ONESHOT=(kafka-topicos)

ODS_SCRIPT=$(readlink -f "$0")
ODS_DIR_APP=$(dirname "$ODS_SCRIPT")
ODS_DIR_BUILDS=$(dirname "$ODS_DIR_APP")
ODS_DIR_COMUM="$ODS_DIR_BUILDS/comum"
cd "$ODS_DIR_APP"

[[ -f "$APP.env" ]] || { echo "$APP.env não encontrado em $ODS_DIR_APP" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
source "./$APP.env"
set +a

MIN_LIVRE_GB=${MIN_LIVRE_GB:-4}
ESPERA_S=${ESPERA_S:-300}
KAFKA_IMG=confluentinc/cp-kafka:latest
UID_GID="$(id -u):$(id -g)"
export UID_GID
PROJETO="ods-$APP"
# Imagens que nenhuma limpeza pode remover (Kafka da turma e bases do SIS-1).
PROTEGIDAS='^(confluentinc/cp-kafka|nvcr\.io/nvidia/l4t|ods/base-gpu)'

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else V=; A=; R=; N=; fi
ok()    { echo "${V}✔${N} $*"; }
aviso() { echo "${A}!${N} $*"; }
erro()  { echo "${R}✘ $*${N}" >&2; exit 1; }
etapa() { echo; echo "== $*"; }

# ---------------------------------------------------------------- compose

# Sem o .secrets.env (ex.: na limpeza ou no status), o compose ainda precisa interpolar os
# ${VAR:?}. Usa um arquivo temporário com valores de mentira; o "subir" exige o arquivo real.
if [[ -f "$APP.secrets.env" ]]; then
  ODS_SEGREDOS_ARQ="$APP.secrets.env"
else
  ODS_SEGREDOS_ARQ=$(mktemp)
  trap 'rm -f "$ODS_SEGREDOS_ARQ"' EXIT
  for _v in "${SEGREDOS[@]}"; do echo "$_v=nao-definido" >>"$ODS_SEGREDOS_ARQ"; done
fi

dc() { docker compose --env-file "$APP.env" --env-file "$ODS_SEGREDOS_ARQ" "$@"; }

ajuda() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$ODS_SCRIPT"; }

# Todos os perfis do compose, já no formato "--profile x --profile y".
PERFIS=()
carregar_perfis() {
  PERFIS=()
  local p
  while read -r p; do [[ -n "$p" ]] && PERFIS+=(--profile "$p"); done < <(dc config --profiles 2>/dev/null)
  return 0
}

# Mapa serviço -> imagem, só dos serviços com "build:" (o que esta build constrói).
declare -A IMG=()
carregar_imagens() {
  IMG=()
  local svc img
  while IFS=$'\t' read -r svc img; do
    [[ -n "$svc" ]] && IMG[$svc]=$img
  done < <(dc "${PERFIS[@]}" config --format json | python3 -c '
import json, sys
for nome, s in json.load(sys.stdin).get("services", {}).items():
    if "build" in s and s.get("image"):
        print(nome + "\t" + s["image"])
')
}

# Todas as imagens que a build usa (construídas e baixadas), uma por linha.
imagens_da_build() { dc "${PERFIS[@]}" config --images 2>/dev/null | sort -u; }

# ---------------------------------------------------------------- conferências

livre_gb() { df -BG --output=avail / | tail -1 | tr -dc '0-9'; }

checar_disco() {
  local livre; livre=$(livre_gb)
  if (( livre < MIN_LIVRE_GB )); then
    erro "só ${livre} GB livres no disco (mínimo ${MIN_LIVRE_GB} GB). Abaixo disso o Kafka da turma cai.
  Veja onde está o espaço com: docker system df
  Para liberar a build de outra aplicação: ../ods.sh trocar $APP"
  fi
  ok "disco: ${livre} GB livres"
}

checar_segredos() {
  (( ${#SEGREDOS[@]} )) || return 0
  [[ -f "$APP.secrets.env" ]] \
    || erro "falta o $APP.secrets.env. Crie com: cp $APP.secrets.env.exemplo $APP.secrets.env e preencha."
  local v
  for v in "${SEGREDOS[@]}"; do
    grep -qE "^${v}=.+" "$APP.secrets.env" || erro "$v está vazio em $APP.secrets.env"
  done
  ok "segredos preenchidos"
}

checar_kafka() {
  local estado
  estado=$(docker ps -a --filter name='^kafka$' --format '{{.Status}}' || true)
  [[ -n "$estado" ]] || erro "o container 'kafka' da turma não existe nesta placa."
  [[ "$estado" == Up* ]] || erro "o Kafka da turma está parado ($estado). Avise o grupo dono; para religar: docker start kafka"
  if docker run --rm "$KAFKA_IMG" kafka-broker-api-versions --bootstrap-server "$KAFKA_BROKER" 2>/dev/null \
       | grep -q -- '-> ('; then
    ok "Kafka da turma respondendo em $KAFKA_BROKER"
  else
    erro "o Kafka da turma está de pé, mas não responde em $KAFKA_BROKER (listener mudou? veja docker inspect kafka)."
  fi
}

# Ajudantes para o checar_entradas de cada aplicação: só avisam, não param a subida.
entrada_arquivo() {
  if [[ -f "$1" ]]; then ok "$2: $1"; else aviso "sem $1: $3"; fi
}
entrada_pasta() {
  if compgen -G "$1/*" >/dev/null; then ok "$2: $1"; else aviso "pasta $1 vazia ou ausente: $3"; fi
}

checar_http() {   # checar_http <url> <nome>
  local codigo
  codigo=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$1" || true)
  if [[ "$codigo" =~ ^(2|3) ]]; then ok "$2 respondendo ($1)"; else aviso "$2 ainda não respondeu em $1 (HTTP $codigo)"; fi
}

# ---------------------------------------------------------------- construir e subir

construir() {
  local reconstruir=$1 grupo s faltam
  carregar_imagens
  local -A nas_etapas=()
  for grupo in "${ETAPAS[@]}"; do for s in $grupo; do nas_etapas[$s]=1; done; done
  # Serviço do "up" com build esquecido em ETAPAS vai numa etapa final, para não faltar imagem.
  # Serviços de perfis fora de ETAPAS não são construídos aqui (o "run" constrói se precisar).
  local resto=()
  while read -r s; do
    [[ -n "$s" && -n "${IMG[$s]:-}" && -z "${nas_etapas[$s]:-}" ]] && resto+=("$s")
  done < <(dc config --services)
  local etapas=("${ETAPAS[@]}")
  (( ${#resto[@]} )) && etapas+=("${resto[*]}")

  for grupo in "${etapas[@]}"; do
    faltam=()
    for s in $grupo; do
      [[ -n "${IMG[$s]:-}" ]] || erro "ETAPAS cita '$s', que não tem build no docker-compose.yml"
      if [[ "$reconstruir" == 1 ]] || ! docker image inspect "${IMG[$s]}" >/dev/null 2>&1; then
        faltam+=("$s")
      fi
    done
    (( ${#faltam[@]} )) || continue
    etapa "Construindo: ${faltam[*]}"
    dc "${PERFIS[@]}" build "${faltam[@]}" 2>&1 | tee -a "$HOME/build-$APP.log"
    docker builder prune -af >/dev/null
    checar_disco
  done
  ok "todas as imagens da build existem"
}

eh_oneshot() { local o; for o in "${ONESHOT[@]}"; do [[ "$o" == "$1" ]] && return 0; done; return 1; }

esperar_servicos() {
  local limite=$((SECONDS + ESPERA_S)) svc estado saude codigo pendentes=()
  # Só os serviços do "up" (sem perfil); containers de perfis sob demanda não contam.
  local -A do_up=()
  while read -r svc; do [[ -n "$svc" ]] && do_up[$svc]=1; done < <(dc config --services)
  while (( SECONDS < limite )); do
    pendentes=()
    while IFS='|' read -r svc estado saude codigo; do
      [[ -n "$svc" && -n "${do_up[$svc]:-}" ]] || continue
      if eh_oneshot "$svc"; then
        [[ "$estado" == exited && "$codigo" == 0 ]] || pendentes+=("$svc")
      elif [[ -n "$saude" ]]; then
        [[ "$saude" == healthy ]] || pendentes+=("$svc")
      else
        [[ "$estado" == running ]] || pendentes+=("$svc")
      fi
    done < <(dc ps -a --format '{{.Service}}|{{.State}}|{{.Health}}|{{.ExitCode}}')
    if (( ${#pendentes[@]} == 0 )); then ok "serviços de pé"; return 0; fi
    sleep 5
  done
  for svc in "${pendentes[@]}"; do aviso "$svc não ficou pronto: veja  docker compose --env-file $APP.env --env-file $APP.secrets.env logs --tail 30 $svc"; done
  erro "nem todos os serviços subiram em $((ESPERA_S / 60)) minutos"
}

subir() {
  local reconstruir=0
  [[ "${1:-}" == "--reconstruir" ]] && reconstruir=1

  etapa "Conferindo a placa"
  command -v docker >/dev/null || erro "docker não encontrado"
  command -v python3 >/dev/null || erro "python3 não encontrado"
  checar_segredos
  checar_disco
  checar_kafka
  if declare -F checar_entradas >/dev/null; then checar_entradas; fi

  etapa "Código (commits fixados no $APP.env)"
  ./preparar-codigo.sh

  carregar_perfis
  construir "$reconstruir"

  etapa "Subindo"
  dc up -d --remove-orphans
  esperar_servicos
  if declare -F pos_subida >/dev/null; then pos_subida; fi
  echo
  echo "Pronto. Estado: ./$APP.sh status · parar: ./$APP.sh parar · remover: ./limpar.sh"
}

status() {
  carregar_perfis
  dc "${PERFIS[@]}" ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  echo
  df -h /
  echo
  docker ps -a --filter name='^kafka$' --format 'Kafka da turma: {{.Status}}'
  local rel; rel=$(ls -t resultados/aceite-"$APP"-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

parar() {
  carregar_perfis
  dc "${PERFIS[@]}" down --remove-orphans
  ok "build parada. Bancos e dados continuam nos volumes (para remover: ./limpar.sh)."
}

# ---------------------------------------------------------------- teste de aceitação
#
# O serviço "aceite" (perfil aceite) faz o papel da aplicação ou observa a cadeia pelo Kafka.
# Roteiro no testar() de cada aplicação:
#   aceite_conferir s1 s2 …   exige os serviços rodando
#   aceite_iniciar            sobe o "aceite" e espera a linha PRONTO
#   <passo externo>; aceite_passo <nome>   ex.: tocar o vídeo e avisar o teste
#   aceite_concluir           espera o fim, mostra o relatório e devolve o código do teste

aceite_conferir() {
  checar_kafka
  local svc
  for svc in "$@"; do
    [[ "$(dc ps --format '{{.State}}' "$svc" 2>/dev/null)" == running ]] \
      || erro "$svc não está rodando. Rode ./$APP.sh subir antes."
  done
  mkdir -p resultados
  rm -f resultados/.passo-*
}

aceite_iniciar() {
  etapa "Iniciando o teste de aceitação (serviço aceite)"
  dc --profile aceite up -d --force-recreate aceite >/dev/null
  local limite=$((SECONDS + 120))
  until dc --profile aceite logs aceite 2>/dev/null | grep -q PRONTO; do
    [[ "$(dc --profile aceite ps -a --format '{{.State}}' aceite)" == running ]] \
      || { dc --profile aceite logs aceite; erro "o teste terminou antes de ficar pronto"; }
    (( SECONDS < limite )) || erro "o teste não ficou pronto em 2 minutos"
    sleep 2
  done
  ok "teste escutando o Kafka"
}

aceite_passo() { touch "resultados/.passo-$1"; }

aceite_concluir() {
  etapa "Esperando o teste concluir"
  local codigo rel
  codigo=$(docker wait "$(dc --profile aceite ps -aq aceite)")
  echo
  dc --profile aceite logs --no-log-prefix aceite | sed -n '/^Teste de aceitação/,$p'
  rel=$(ls -t resultados/aceite-"$APP"-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Relatório: $ODS_DIR_APP/$rel (e .json com as mensagens de amostra)"; }
  rm -f resultados/.passo-*
  return "$codigo"
}

ods_principal() {
  case "${1:-subir}" in
    subir)  subir "${2:-}" ;;
    testar)
      if declare -F testar >/dev/null; then testar
      else aviso "a build do $APP ainda não tem teste de aceitação (a validação fica para uma etapa seguinte)."; fi ;;
    status) status ;;
    parar)  parar ;;
    -h|--help|ajuda) ajuda ;;
    *) erro "comando desconhecido: $1 (use subir, testar, status ou parar)" ;;
  esac
}

# ---------------------------------------------------------------- limpeza

# Repositórios de um .env: toda variável <REPO>_REF vira o clone SRC_DIR/<repo>.
repos_do_env() { grep -oE '^[A-Z0-9]+_REF=' "$1" | sed 's/_REF=$//' | tr 'A-Z' 'a-z' | sort -u; }

# Imagens que a build de outra aplicação usa (para "trocar" sem jogar fora o que a próxima precisa).
imagens_de_outra_app() {
  local outra=$1 dir="$ODS_DIR_BUILDS/$1"
  [[ -f "$dir/$outra.env" ]] || erro "--manter $outra: não existe $dir/$outra.env"
  ( cd "$dir"
    sec="$outra.secrets.env"
    if [[ ! -f "$sec" ]]; then
      sec=$(mktemp)
      trap 'rm -f "$sec"' EXIT
      grep -oE '^[A-Z0-9_]+=' "$outra.secrets.env.exemplo" 2>/dev/null | sed 's/=$/=nao-definido/' >"$sec" || true
    fi
    perfis=()
    while read -r p; do [[ -n "$p" ]] && perfis+=(--profile "$p"); done \
      < <(docker compose --env-file "$outra.env" --env-file "$sec" config --profiles 2>/dev/null)
    docker compose --env-file "$outra.env" --env-file "$sec" "${perfis[@]}" config --images 2>/dev/null | sort -u
  )
}

remover_containers() {
  local volumes=$1
  local args=(down --remove-orphans)
  [[ "$volumes" == 1 ]] && args+=(-v)
  if ! dc "${PERFIS[@]}" "${args[@]}"; then
    # O compose pode falhar (clone apagado, .env incompleto). Cai para os rótulos do projeto.
    aviso "o docker compose down falhou; removendo pelos rótulos do projeto $PROJETO"
    docker ps -aq --filter "label=com.docker.compose.project=$PROJETO" | xargs -r docker rm -f
    docker network ls -q --filter "label=com.docker.compose.project=$PROJETO" | xargs -r docker network rm
    if [[ "$volumes" == 1 ]]; then
      docker volume ls -q --filter "label=com.docker.compose.project=$PROJETO" | xargs -r docker volume rm
    fi
  fi
}

remover_imagens() {
  local manter=$1 img
  local -A protegida=()
  if [[ -n "$manter" ]]; then
    while read -r img; do [[ -n "$img" ]] && protegida[$img]=1; done < <(imagens_de_outra_app "$manter")
  fi
  local alvo=()
  while read -r img; do
    [[ -n "$img" ]] || continue
    [[ "$img" =~ $PROTEGIDAS ]] && continue
    if [[ -n "${protegida[$img]:-}" ]]; then echo "  mantida (o $manter usa): $img"; continue; fi
    docker image inspect "$img" >/dev/null 2>&1 && alvo+=("$img")
  done < <(imagens_da_build)
  if (( ${#alvo[@]} == 0 )); then ok "nenhuma imagem da build para remover"; else
    for img in "${alvo[@]}"; do
      # Sem -f: imagem em uso por um container (de qualquer projeto) não sai.
      if docker rmi "$img" >/dev/null 2>&1; then echo "  removida: $img"
      else aviso "não removida (em uso por algum container?): $img"; fi
    done
  fi
  docker builder prune -af >/dev/null
  ok "cache de build limpo (docker builder prune -af)"
}

remover_codigo() {
  local repo outro outros=() dir
  local -A usado=()
  for outro in "$ODS_DIR_BUILDS"/*/*.env; do
    [[ "$outro" == "$ODS_DIR_APP/$APP.env" ]] && continue
    [[ "$outro" == *.secrets.env ]] && continue
    while read -r repo; do usado[$repo]=1; done < <(repos_do_env "$outro")
  done
  [[ -n "${SRC_DIR:-}" && "$SRC_DIR" == /* && "$SRC_DIR" != / ]] || erro "SRC_DIR inválido: '${SRC_DIR:-}'"
  while read -r repo; do
    dir="$SRC_DIR/$repo"
    if [[ -n "${usado[$repo]:-}" ]]; then outros+=("$repo"); continue; fi
    if [[ -d "$dir/.git" ]]; then rm -rf -- "$dir"; echo "  clone removido: $dir"; fi
  done < <(repos_do_env "$APP.env")
  (( ${#outros[@]} )) && echo "  mantidos (outras builds usam): ${outros[*]}"
  ok "clones exclusivos do $APP removidos"
}

limpar_build() {
  local imagens=0 dados=0 codigo=0 manter="" sim=0
  while (( $# )); do
    case "$1" in
      --imagens) imagens=1 ;;
      --dados)   dados=1 ;;
      --codigo)  codigo=1 ;;
      --tudo)    imagens=1; dados=1; codigo=1 ;;
      --manter)  shift; manter=${1:?--manter precisa do nome de outra aplicação (ex.: a5)} ;;
      --sim-ao-confirmar-dados) sim=1 ;;
      -h|--help|ajuda) ajuda; return 0 ;;
      *) erro "opção desconhecida: $1 (use --imagens, --dados, --codigo, --tudo, --manter <app>)" ;;
    esac
    shift
  done

  command -v docker >/dev/null || erro "docker não encontrado"
  echo "Disco antes:"; df -h / | tail -1

  if (( dados )) && (( ! sim )); then
    echo
    aviso "--dados apaga os volumes do $APP (bancos, clipes, métricas, caches de modelo):"
    docker volume ls --filter "label=com.docker.compose.project=$PROJETO" --format '    {{.Name}}'
    if declare -F lembrete_backup >/dev/null; then lembrete_backup; fi
    local resposta
    read -r -p "Para confirmar, digite o nome da aplicação ($APP): " resposta
    [[ "$resposta" == "$APP" ]] || erro "confirmação não confere; nada foi apagado."
  fi

  carregar_perfis
  etapa "Containers do $APP"
  remover_containers "$dados"
  ok "containers removidos$( (( dados )) && echo ' (com os volumes)' || echo '; volumes mantidos')"

  if (( imagens )); then etapa "Imagens do $APP"; remover_imagens "$manter"; fi
  if (( codigo )); then etapa "Clones em ${SRC_DIR:-?}"; remover_codigo; fi

  echo
  echo "Disco depois:"; df -h / | tail -1
  [[ -d resultados ]] && echo "(a pasta resultados/ foi mantida: é evidência)"
  return 0
}
