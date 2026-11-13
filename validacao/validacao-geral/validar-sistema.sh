#!/usr/bin/env bash
# validar-sistema.sh <app> [--queda <serviço>] — critérios de sistema S1–S9 de uma build ODS na Jetson.
#
# Confere a build que está de pé (projeto Docker "ods-<app>", criado por builds/<app>/<app>.sh):
#   S1 containers estáveis e saudáveis          S6 imagens com versão (sem latest)
#   S2 memória (2.500 MB/serviço, 5.150 MB total) S7 disco dentro da política (>= 4 GB livres)
#   S3 só as portas da build, internas em 127.0.0.1  S8 segredos fora do Git e das imagens
#   S4 dados em volumes                         S9 logs sem erros recorrentes / sem reinício em laço
#   S5 política de reinício (e, com --queda <serviço>, derruba o serviço e confere que ele volta)
#
# Saída: linhas OK / FALHA / AVISO, também gravadas em validacao/<app>/evidencias/sistema-<data>.txt.
# Código de saída = número de falhas (0 = aprovado). Não altera nada, exceto com --queda.
set -uo pipefail

APP=${1:?uso: validar-sistema.sh <app> [--queda <serviço>]}
shift
QUEDA=""
while (( $# )); do
  case "$1" in
    --queda) shift; QUEDA=${1:?--queda precisa do nome do serviço} ;;
    *) echo "opção desconhecida: $1" >&2; exit 64 ;;
  esac
  shift
done

RAIZ=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
BUILD="$RAIZ/builds/$APP"
[[ -f "$BUILD/$APP.env" ]] || { echo "não existe $BUILD/$APP.env" >&2; exit 64; }
PROJ="ods-$APP"
SAIDA="$RAIZ/validacao/$APP/evidencias/sistema-$(date +%F-%H%M).txt"
mkdir -p "$(dirname "$SAIDA")"
falhas=0
log()   { echo "$*" | tee -a "$SAIDA"; }
ok()    { log "OK    $*"; }
falha() { log "FALHA $*"; falhas=$((falhas + 1)); }
aviso() { log "AVISO $*"; }
secao() { log ""; log "== $*"; }

# Portas que cada build publica (ver builds/README.md). LOCAIS precisam estar em 127.0.0.1.
declare -A PUBLICAS=( [a1]="5500" [a2]="8000 8001 8082" [a3]="8501" [a4]="3000 8000 18084"
                      [a5]="8095" [a6]="8086" [a7]="8000" [a8]="3000 8081" )
declare -A LOCAIS=( [a1]="8010 18084 8000" [a2]="18084" [a3]="18084 8000" [a4]="8005"
                    [a5]="8000 18084" [a6]="" [a7]="" [a8]="18084 8000" )
# Containers que terminam sozinhos (one-shots e serviços sob demanda): exited 0 é o esperado.
SOB_DEMANDA='^(kafka-topicos|aceite|p4|i1|i3|i5|i7|i8|i4-amostra)$'
LIMITE_SVC_MB=2500
LIMITE_TOTAL_MB=5150
MIN_LIVRE_GB=4

mapfile -t CONTAINERS < <(docker ps -a --filter "label=com.docker.compose.project=$PROJ" --format '{{.Names}}' | sort)
servico_de() { docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$1"; }

log "== Validação de sistema do $APP ($PROJ) — $(date '+%F %T') — $(uname -n)"
(( ${#CONTAINERS[@]} )) || { falha "nenhum container do projeto $PROJ: suba com builds/$APP/$APP.sh"; exit "$falhas"; }

# ------------------------------------------------------------------ S1
secao "S1 containers estáveis e saudáveis"
for c in "${CONTAINERS[@]}"; do
  svc=$(servico_de "$c")
  read -r estado saude codigo < <(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}} {{.State.ExitCode}}' "$c")
  if [[ "$estado" == running && "$saude" =~ ^(healthy|-)$ ]]; then ok "$svc rodando$([[ "$saude" == - ]] || echo " ($saude)")"
  elif [[ "$estado" == running ]]; then falha "$svc rodando, mas health=$saude"
  elif [[ "$estado" == exited && "$codigo" == 0 && "$svc" =~ $SOB_DEMANDA ]]; then ok "$svc terminou normalmente (sob demanda)"
  elif [[ "$estado" == exited && "$svc" == i1 ]]; then aviso "$svc saiu com $codigo (esperado no fim do vídeo: pendência MOD-1)"
  else falha "$svc em $estado (código $codigo)"; fi
done

# ------------------------------------------------------------------ S2
secao "S2 memória"
total=0
while IFS='|' read -r nome uso; do
  [[ " ${CONTAINERS[*]} " == *" $nome "* ]] || continue
  valor=${uso%% /*}
  mb=$(awk -v v="$valor" 'BEGIN{n=v+0; if(v~/GiB/)n*=1024; else if(v~/KiB/)n/=1024; else if(v~/B$/ && v!~/[KMG]iB/)n/=1048576; printf "%d", n}')
  total=$((total + mb))
  if (( mb > LIMITE_SVC_MB )); then falha "$(servico_de "$nome") usa $mb MB (> $LIMITE_SVC_MB)"
  else ok "$(servico_de "$nome") usa $mb MB"; fi
done < <(docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}')
if (( total > LIMITE_TOTAL_MB )); then falha "total da build: $total MB (> $LIMITE_TOTAL_MB)"; else ok "total da build: $total MB"; fi
log "      $(free -m | awk '/^Mem:/{print "memória da placa: " $3 " MB usados de " $2 " MB"}')"

# ------------------------------------------------------------------ S3
secao "S3 portas publicadas"
permitidas=" ${PUBLICAS[$APP]:-} ${LOCAIS[$APP]:-} "
for c in "${CONTAINERS[@]}"; do
  svc=$(servico_de "$c")
  while read -r ligacao; do
    [[ -n "$ligacao" ]] || continue
    ip=${ligacao%:*}; porta=${ligacao##*:}
    if [[ "$permitidas" != *" $porta "* ]]; then falha "$svc publica $ip:$porta, fora da lista da build"
    elif [[ " ${LOCAIS[$APP]:-} " == *" $porta "* && "$ip" != 127.0.0.1 ]]; then falha "$svc publica a API interna $porta em $ip (deveria ser 127.0.0.1)"
    else ok "$svc publica $ip:$porta"; fi
  done < <(docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{.HostIp}}:{{.HostPort}}{{"\n"}}{{end}}{{end}}' "$c" | sed 's/^:::/[::]:/' | sort -u)
done
aviso "o Docker publica por cima do ufw: confira de fora da rede do laboratório (ex.: celular em dados móveis) as portas públicas: ${PUBLICAS[$APP]:-nenhuma}"

# ------------------------------------------------------------------ S4
secao "S4 dados em volumes"
mapfile -t VOLUMES < <(docker volume ls -q --filter "label=com.docker.compose.project=$PROJ")
(( ${#VOLUMES[@]} )) || aviso "a build não tem volumes nomeados"
for v in "${VOLUMES[@]}"; do
  usado=$(docker ps -a --filter "volume=$v" --format '{{.Names}}' | wc -l)
  if (( usado )); then ok "volume $v montado por $usado container(s)"; else aviso "volume $v sem container (órfão de uma execução anterior?)"; fi
done
for c in "${CONTAINERS[@]}"; do
  binds=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{if not .RW}}{{else}}{{.Destination}} {{end}}{{end}}{{end}}' "$c")
  [[ -n "$binds" ]] && aviso "$(servico_de "$c") grava em pasta do host (bind RW): $binds"
done

# ------------------------------------------------------------------ S5
secao "S5 reinício automático"
for c in "${CONTAINERS[@]}"; do
  svc=$(servico_de "$c")
  [[ "$svc" =~ $SOB_DEMANDA ]] && continue
  politica=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c")
  if [[ "$politica" =~ ^(unless-stopped|always|on-failure)$ ]]; then ok "$svc com restart=$politica"
  else falha "$svc com restart=$politica"; fi
done
if [[ -n "$QUEDA" ]]; then
  c=$(docker ps --filter "label=com.docker.compose.project=$PROJ" --filter "label=com.docker.compose.service=$QUEDA" --format '{{.Names}}' | head -1)
  if [[ -z "$c" ]]; then falha "--queda $QUEDA: serviço não está rodando"
  else
    antes=$(docker inspect -f '{{.RestartCount}}' "$c")
    log "      derrubando $QUEDA (docker kill) e esperando até 90 s"
    docker kill "$c" >/dev/null
    voltou=0
    for _ in $(seq 1 45); do
      sleep 2
      [[ "$(docker inspect -f '{{.State.Status}} {{.RestartCount}}' "$c")" == "running $((antes + 1))"* ]] && { voltou=1; break; }
    done
    if (( voltou )); then ok "$QUEDA voltou sozinho depois da queda"
    else falha "$QUEDA não voltou em 90 s (religue com: cd builds/$APP && ./$APP.sh subir)"; fi
  fi
else
  aviso "teste de queda não executado (use --queda <serviço>, ex.: --queda $(servico_de "${CONTAINERS[0]}"))"
fi

# ------------------------------------------------------------------ S6
secao "S6 imagens com versão"
for c in "${CONTAINERS[@]}"; do
  img=$(docker inspect -f '{{.Config.Image}}' "$c"); svc=$(servico_de "$c")
  if [[ "$img" == confluentinc/cp-kafka:latest ]]; then aviso "$svc usa $img (a mesma imagem do Kafka da turma, só para criar tópicos)"
  elif [[ "$img" != *:* || "$img" == *:latest ]]; then falha "$svc usa $img, sem versão fixada"
  else ok "$svc usa $img"; fi
done

# ------------------------------------------------------------------ S7
secao "S7 disco"
livre=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
if (( livre < MIN_LIVRE_GB )); then falha "só $livre GB livres em / (mínimo $MIN_LIVRE_GB GB)"; else ok "$livre GB livres em /"; fi
docker system df --format '      {{.Type}}: {{.Size}} ({{.Reclaimable}} recuperável)' | tee -a "$SAIDA"

# ------------------------------------------------------------------ S8
secao "S8 segredos"
cd "$RAIZ"
if git ls-files --error-unmatch "builds/$APP/$APP.secrets.env" >/dev/null 2>&1; then falha "builds/$APP/$APP.secrets.env está versionado no Git"
else ok "$APP.secrets.env fora do Git"; fi
if [[ -f "builds/$APP/$APP.secrets.env" ]]; then
  git check-ignore -q "builds/$APP/$APP.secrets.env" && ok ".gitignore cobre o $APP.secrets.env" || falha ".gitignore não cobre o $APP.secrets.env"
  while IFS='=' read -r chave valor; do
    [[ -z "$chave" || "$chave" == \#* || -z "$valor" ]] && continue
    if (( ${#valor} < 8 )); then aviso "$chave tem menos de 8 caracteres: curto demais para procurar nas imagens (e fraco)"; continue; fi
    vazou=""
    for img in $(docker ps -a --filter "label=com.docker.compose.project=$PROJ" --format '{{.Image}}' | sort -u); do
      docker image inspect -f '{{json .Config.Env}}{{json .Config.Labels}}' "$img" 2>/dev/null | grep -qF -- "$valor" && vazou+=" $img"
      docker history --no-trunc --format '{{.CreatedBy}}' "$img" 2>/dev/null | grep -qF -- "$valor" && vazou+=" $img(histórico)"
    done
    if [[ -n "$vazou" ]]; then falha "valor de $chave aparece dentro de imagem:$vazou"; else ok "$chave não aparece em nenhuma imagem"; fi
  done < "builds/$APP/$APP.secrets.env"
else
  ok "a build não tem $APP.secrets.env nesta placa"
fi

# ------------------------------------------------------------------ S9
secao "S9 logs (últimos 30 min)"
for c in "${CONTAINERS[@]}"; do
  svc=$(servico_de "$c")
  reinicios=$(docker inspect -f '{{.RestartCount}}' "$c")
  erros=$(docker logs --since 30m "$c" 2>&1 | grep -ciE 'traceback|exception|fatal|\berror\b' || true)
  if (( reinicios > 3 )) && [[ "$svc" != i1 ]]; then falha "$svc reiniciou $reinicios vezes"
  elif (( erros > 20 )); then aviso "$svc tem $erros linhas de erro nos últimos 30 min (docker logs --since 30m $c)"
  else ok "$svc: $erros linha(s) de erro, $reinicios reinício(s)"; fi
done

log ""
if (( falhas == 0 )); then log "RESULTADO: APROVADO nos critérios de sistema"; else log "RESULTADO: $falhas falha(s)"; fi
log "Evidência: $SAIDA"
exit "$falhas"
