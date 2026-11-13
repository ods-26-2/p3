#!/usr/bin/env bash
# a8.sh — monta, sobe e testa a build do A8 na Jetson (P3 / SIS-1).
#
#   ./a8.sh                o mesmo que ./a8.sh subir
#   ./a8.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a8.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a8.sh testar         teste de aceitação do A8: I7, vídeo do P4 e pedidos ao S4, S5 e S2
#   ./a8.sh placas-video   o I7 lê as placas de VIDEO_DIR/I7_VIDEO e mostra as decisões do A8
#   ./a8.sh status         containers, disco, Kafka da turma e último resultado de teste
#   ./a8.sh parar          derruba a build (mantém banco, clipes e métricas)
#
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), I7_N (imagens do I7 no teste, padrão 5; só com I7_FONTE=imagens)
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
[[ -f a8.env ]] || { echo "a8.env não encontrado em $(pwd)"; exit 1; }
set -a
# shellcheck source=/dev/null
source ./a8.env
set +a

MIN_LIVRE_GB=${MIN_LIVRE_GB:-4}
I7_N=${I7_N:-5}
KAFKA_IMG=confluentinc/cp-kafka:latest
UID_GID="$(id -u):$(id -g)"
export UID_GID
PERFIS=(--profile video --profile i3 --profile i7 --profile aceite)

if [[ -t 1 ]]; then V=$'\e[32m'; A=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else V=; A=; R=; N=; fi
ok()    { echo "${V}✔${N} $*"; }
aviso() { echo "${A}!${N} $*"; }
erro()  { echo "${R}✘ $*${N}" >&2; exit 1; }
etapa() { echo; echo "== $*"; }

dc() { docker compose --env-file a8.env --env-file a8.secrets.env "$@"; }

declare -A IMG=(
  [a8-backend]="ods-a8-backend:$A8_REF" [a8-frontend]="ods-a8-frontend:$A8_REF" [i7]="ods-i7:$I7_REF"
  [p4]="ods-p4:$P4_REF" [i1]="ods-i1:$I1_REF" [i2]="ods-i2:$I2_REF" [i3]="ods-i3:$I3_REF"
  [s1]="ods-s1:$S1_REF" [s4]="ods-s4:$S4_REF" [s5]="ods-s5:$S5_REF" [aceite]="ods-aceite-a8:1"
)
# Ordem de construção: a que deixa mais cache primeiro, as maiores por último, sozinhas.
ETAPAS=("s4" "p4 i2 i3 s1 s5 a8-backend a8-frontend aceite" "i7" "i1")

livre_gb() { df -BG --output=avail / | tail -1 | tr -dc '0-9'; }

checar_disco() {
  local livre; livre=$(livre_gb)
  if (( livre < MIN_LIVRE_GB )); then
    erro "só ${livre} GB livres no disco (mínimo ${MIN_LIVRE_GB} GB). Abaixo disso o Kafka da turma cai.
  Veja onde está o espaço com: docker system df"
  fi
  ok "disco: ${livre} GB livres"
}

VOLUME_BANCO=ods-a8_a8-mysql
# Estado das imagens construídas por este script: serviço, id da imagem e hash da receita.
ESTADO_IMAGENS=.estado-imagens

# Na primeira subida (sem a8.secrets.env e sem banco), gera senhas aleatórias. Se o banco já
# existe, a senha está gravada nele: gerar outra quebraria o backend, então para e explica.
garantir_segredos() {
  if [[ ! -f a8.secrets.env ]]; then
    if docker volume inspect "$VOLUME_BANCO" >/dev/null 2>&1; then
      erro "falta o a8.secrets.env, mas o banco ($VOLUME_BANCO) já existe com uma senha gravada.
  Recrie o a8.secrets.env com a MESMA A8_DB_PASSWORD de antes (ou apague o banco: ./limpar.sh --dados)."
    fi
    ( umask 077
      python3 - > a8.secrets.env <<'PY'
import secrets
print("# Gerado por ./a8.sh na primeira subida. NÃO vai para o Git. Guarde uma cópia.")
print("A8_DB_PASSWORD=" + secrets.token_hex(16))
print("A8_JWT_SECRET=" + secrets.token_hex(32))
PY
    )
    ok "a8.secrets.env criado com senhas aleatórias (guarde uma cópia: o banco depende dela)"
  fi
  checar_segredos
}

checar_segredos() {
  [[ -f a8.secrets.env ]] || erro "falta o a8.secrets.env. Crie com: cp a8.secrets.env.exemplo a8.secrets.env e preencha."
  local v
  for v in A8_DB_PASSWORD A8_JWT_SECRET; do
    grep -qE "^${v}=.+" a8.secrets.env || erro "$v está vazio em a8.secrets.env"
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
    erro "o Kafka da turma está de pé, mas não responde em $KAFKA_BROKER (listener mudou?)."
  fi
}

checar_entradas() {
  if [[ -f "$VIDEO_DIR/cam0.mp4" ]]; then ok "vídeo da cadeia: $VIDEO_DIR/cam0.mp4"
  else aviso "sem $VIDEO_DIR/cam0.mp4: a cadeia sobe, mas não há vídeo para o P4 tocar"; fi
  if [[ "${I7_FONTE:-imagens}" == video ]]; then
    if [[ -f "$VIDEO_DIR/$I7_VIDEO" ]]; then ok "I7 vai ler o vídeo $VIDEO_DIR/$I7_VIDEO ($I7_QUADROS_FPS quadros/s)"
    else aviso "sem $VIDEO_DIR/$I7_VIDEO: o I7 não terá o que ler"; fi
  elif compgen -G "$I7_IMAGENS_DIR/*" >/dev/null; then ok "imagens do I7: $I7_IMAGENS_DIR"
  else aviso "sem imagens em $I7_IMAGENS_DIR: o I7 não terá o que ler"; fi
}

# Pastas da placa que a build usa. A do I7 é criada aqui (senão o Docker a cria como root).
checar_pastas() {
  if [[ ! -d "$I7_IMAGENS_DIR" ]]; then
    if mkdir -p "$I7_IMAGENS_DIR" 2>/dev/null; then ok "pasta criada: $I7_IMAGENS_DIR"
    else aviso "não consegui criar $I7_IMAGENS_DIR. Uma vez só: sudo mkdir -p $I7_IMAGENS_DIR && sudo chown $(id -un) $I7_IMAGENS_DIR"; fi
  fi
  [[ -d "$VIDEO_DIR" ]] || aviso "a pasta $VIDEO_DIR não existe: P4, S4 e o I7 em modo vídeo ficam sem entrada"
  return 0
}

# O I7 lê quadros extraídos do vídeo (serviço i7-video; usa a imagem do i7, que precisa existir).
rodar_i7_video() {
  docker image inspect "${IMG[i7]}" >/dev/null 2>&1 || erro "a imagem ${IMG[i7]} não existe; rode ./a8.sh subir antes"
  [[ -f "$VIDEO_DIR/$I7_VIDEO" ]] || erro "sem $VIDEO_DIR/$I7_VIDEO para o I7 ler"
  dc --profile i7 run --rm i7-video | grep -E '^\[QUADROS\]|^\[[0-9]+/|Publicação:|PUBLICAÇÃO' \
    || aviso "o I7 terminou com erro"
}

# Decisões do A8 (log do a8-backend) desde o instante $1.
decisoes_desde() {
  docker logs --since "$1" "$(dc ps -q a8-backend)" 2>&1 | grep -E '\[KAFKA\].*->|\[CANCELA\]' || echo "  nenhuma"
}

placas_video() {
  etapa "Conferindo"
  checar_segredos
  checar_kafka
  [[ "$(dc ps --format '{{.State}}' a8-backend 2>/dev/null)" == running ]] \
    || erro "a8-backend não está rodando. Rode ./a8.sh subir antes."
  local t0; t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  etapa "I7 lendo as placas de $VIDEO_DIR/$I7_VIDEO ($I7_QUADROS_FPS quadros/s, câmera $I7_SOURCE_ID)"
  rodar_i7_video
  sleep 3
  etapa "Decisões do A8"
  decisoes_desde "$t0"
}

# Hash da receita de cada serviço: a seção "build" do compose já interpolada (contexto,
# Dockerfile do P3, target, args). O código das equipes já entra pela tag (commit fixado);
# o hash pega as mudanças do lado do P3 que não mudam a tag.
receitas() {
  dc "${PERFIS[@]}" config --format json | python3 -c '
import hashlib, json, sys
for nome, s in json.load(sys.stdin)["services"].items():
    if "build" in s:
        print(nome, hashlib.sha256(json.dumps(s["build"], sort_keys=True).encode()).hexdigest()[:16])
'
}

registrar_imagem() {   # registrar_imagem <serviço> <hash>
  local id; id=$(docker image inspect -f '{{.Id}}' "${IMG[$1]}")
  { grep -v "^$1 " "$ESTADO_IMAGENS" 2>/dev/null || true; echo "$1 $id $2"; } > "$ESTADO_IMAGENS.tmp"
  mv "$ESTADO_IMAGENS.tmp" "$ESTADO_IMAGENS"
}

construir() {
  local reconstruir=$1 grupo s faltam motivo id_atual reg_id reg_hash
  local -A RECEITA=()
  while read -r s h; do RECEITA[$s]=$h; done < <(receitas)
  for grupo in "${ETAPAS[@]}"; do
    faltam=()
    for s in $grupo; do
      motivo=""
      if [[ "$reconstruir" == 1 ]]; then motivo="--reconstruir"
      elif ! id_atual=$(docker image inspect -f '{{.Id}}' "${IMG[$s]}" 2>/dev/null); then motivo="imagem não existe"
      else
        read -r _ reg_id reg_hash < <(grep "^$s " "$ESTADO_IMAGENS" 2>/dev/null || echo "- - -")
        if [[ "$reg_hash" == - ]]; then
          registrar_imagem "$s" "${RECEITA[$s]}"   # imagem anterior a este controle: adotada como está
        elif [[ "$reg_hash" != "${RECEITA[$s]}" ]]; then motivo="receita do P3 mudou"
        elif [[ "$reg_id" != "$id_atual" ]]; then registrar_imagem "$s" "${RECEITA[$s]}"
        fi
      fi
      [[ -n "$motivo" ]] && { faltam+=("$s"); echo "  $s: $motivo"; }
    done
    (( ${#faltam[@]} )) || continue
    etapa "Construindo: ${faltam[*]}"
    dc "${PERFIS[@]}" build "${faltam[@]}" 2>&1 | tee -a "$HOME/build-a8.log"
    for s in "${faltam[@]}"; do registrar_imagem "$s" "${RECEITA[$s]}"; done
    docker builder prune -af >/dev/null
    checar_disco
  done
  ok "todas as imagens da build existem e batem com a receita"
}

esperar_servicos() {
  local limite=$((SECONDS + 240)) linha pendentes svc
  # Só os serviços do "up": containers de perfis sob demanda que já terminaram (p4, i1, aceite
  # depois de um testar) não contam.
  local -A do_up=()
  while read -r svc; do [[ -n "$svc" ]] && do_up[$svc]=1; done < <(dc config --services)
  while (( SECONDS < limite )); do
    pendentes=()
    while IFS='|' read -r svc estado saude codigo; do
      [[ -n "${do_up[$svc]:-}" ]] || continue
      case "$svc" in
        kafka-topicos) [[ "$estado" == exited && "$codigo" == 0 ]] || pendentes+=("$svc") ;;
        a8-mysql|s4|s5) [[ "$saude" == healthy ]] || pendentes+=("$svc") ;;
        *) [[ "$estado" == running ]] || pendentes+=("$svc") ;;
      esac
    done < <(dc ps -a --format '{{.Service}}|{{.State}}|{{.Health}}|{{.ExitCode}}')
    if (( ${#pendentes[@]} == 0 )); then
      ok "serviços de pé"
      return 0
    fi
    sleep 5
  done
  for linha in "${pendentes[@]}"; do aviso "$linha não ficou pronto: veja dc logs --tail 30 $linha"; done
  erro "nem todos os serviços subiram em 4 minutos"
}

subir() {
  local reconstruir=0
  [[ "${1:-}" == "--reconstruir" ]] && reconstruir=1

  etapa "Conferindo a placa"
  command -v docker >/dev/null || erro "docker não encontrado"
  command -v python3 >/dev/null || erro "python3 não encontrado"
  docker compose version >/dev/null 2>&1 || erro "docker compose (v2) não encontrado"
  garantir_segredos
  checar_disco
  checar_kafka
  checar_pastas
  checar_entradas

  etapa "Código (commits fixados no a8.env)"
  ./preparar-codigo.sh

  construir "$reconstruir"

  etapa "Subindo"
  dc up -d --remove-orphans
  esperar_servicos
  # O healthcheck do MySQL (mysqladmin ping) passa mesmo com senha errada; aqui a senha é testada.
  if dc exec -T a8-mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" a8' >/dev/null 2>&1; then
    ok "banco a8 aceita a senha do a8.secrets.env"
  else
    erro "o banco não aceita a A8_DB_PASSWORD do a8.secrets.env (o volume $VOLUME_BANCO guarda a senha
  da primeira subida). Volte a senha antiga no a8.secrets.env, ou apague o banco: ./limpar.sh --dados"
  fi
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/api/health)" == 200 ]]; then
    ok "API do A8 respondendo em http://$JETSON_IP:3000"
  else
    aviso "a API do A8 ainda não respondeu em /api/health"
  fi
  ok "interface do A8: http://$JETSON_IP:8081"
  echo
  echo "Pronto. Para testar a aplicação inteira: ./a8.sh testar"
}

testar() {
  etapa "Conferindo"
  checar_segredos
  checar_kafka
  local svc
  for svc in a8-backend i2 s1 s4 s5; do
    [[ "$(dc ps --format '{{.State}}' "$svc" 2>/dev/null)" == running ]] \
      || erro "$svc não está rodando. Rode ./a8.sh subir antes."
  done
  [[ -f "$VIDEO_DIR/cam0.mp4" ]] || erro "sem $VIDEO_DIR/cam0.mp4 para o P4 tocar"
  mkdir -p resultados
  local t0; t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  etapa "1/5 Iniciando o A8 simulado"
  dc --profile aceite up -d --force-recreate aceite >/dev/null
  local limite=$((SECONDS + 120))
  until dc --profile aceite logs aceite 2>/dev/null | grep -q PRONTO; do
    [[ "$(dc --profile aceite ps -a --format '{{.State}}' aceite)" == running ]] \
      || { dc --profile aceite logs aceite; erro "o teste terminou antes de ficar pronto"; }
    (( SECONDS < limite )) || erro "o teste não ficou pronto em 2 minutos"
    sleep 2
  done
  ok "escutando o Kafka como A8"

  if [[ "${I7_FONTE:-imagens}" == video ]]; then
    etapa "2/5 I7 lendo placas do vídeo $I7_VIDEO ($I7_QUADROS_FPS quadros/s)"
    rodar_i7_video
  elif compgen -G "$I7_IMAGENS_DIR/*" >/dev/null; then
    etapa "2/5 I7 lendo placas ($I7_N imagens)"
    dc --profile i7 run --rm i7 "scripts/aplicacaoModelov5-fast+rodosol.py" -n "$I7_N" \
      | grep -E '^\[[0-9]+/|Publicação:' || aviso "o I7 terminou com erro"
  else
    aviso "sem imagens em $I7_IMAGENS_DIR; o item de placas vai falhar"
  fi

  etapa "3/5 Vídeo: P4 tocando e I1 detectando"
  dc --profile video up -d --force-recreate p4 i1 >/dev/null
  docker wait "$(dc --profile video ps -aq p4)" >/dev/null
  ok "vídeo terminou"

  etapa "4/5 Reenchendo o buffer do S4"
  # O S4 lê o MP4 por conta própria e esvazia o buffer a cada sessão nova do P4.
  dc restart s4 >/dev/null
  ok "S4 reiniciado"

  etapa "5/5 Esperando o A8 simulado concluir os pedidos"
  local codigo
  codigo=$(docker wait "$(dc --profile aceite ps -aq aceite)")
  echo
  dc --profile aceite logs --no-log-prefix aceite | sed -n '/^Teste de aceitação/,$p'

  local rel
  rel=$(ls -t resultados/aceite-a8-*.txt 2>/dev/null | head -1 || true)
  echo
  echo "Decisões do A8 real sobre as placas lidas:"
  {
    echo
    echo "Decisões do A8 real (log do a8-backend desde $t0):"
    docker logs --since "$t0" "$(dc ps -q a8-backend)" 2>&1 | grep '\[KAFKA\]' | grep -- '->' || echo "  nenhuma"
  } | tee -a "${rel:-/dev/null}"
  echo
  [[ -n "$rel" ]] && echo "Relatório: $(pwd)/$rel (e .json com as mensagens de amostra)"
  return "$codigo"
}

status() {
  dc "${PERFIS[@]}" ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
  echo
  df -h /
  echo
  docker ps -a --filter name='^kafka$' --format 'Kafka da turma: {{.Status}}'
  local rel; rel=$(ls -t resultados/aceite-a8-*.txt 2>/dev/null | head -1 || true)
  [[ -n "$rel" ]] && { echo; echo "Último teste ($rel):"; grep '^Resumo' "$rel"; }
  return 0
}

parar() {
  dc "${PERFIS[@]}" down --remove-orphans
  ok "build parada. Banco, clipes e métricas continuam nos volumes."
}

case "${1:-subir}" in
  subir)  subir "${2:-}" ;;
  testar) testar ;;
  placas-video) placas_video ;;
  status) checar_segredos >/dev/null; status ;;
  parar)  checar_segredos >/dev/null; parar ;;
  -h|--help|ajuda) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) erro "comando desconhecido: $1 (use subir, testar, placas-video, status ou parar)" ;;
esac
