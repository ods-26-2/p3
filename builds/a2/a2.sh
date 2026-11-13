#!/usr/bin/env bash
# a2.sh — monta e sobe a build do A2 · Acesso / identificação (VER-2) na Jetson (P3 / SIS-1).
#
#   ./a2.sh                o mesmo que ./a2.sh subir
#   ./a2.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a2.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a2.sh status         containers, disco e Kafka da turma
#   ./a2.sh parar          derruba a build (mantém o registro de acessos e os clipes)
#   ./a2.sh testar         teste de aceitação → resultados/aceite-a2-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a2
SEGREDOS=(A2_AES_KEY)
ETAPAS=("s4 aceite" "a2 a2-cracha i6")

checar_entradas() {
  local chave
  chave=$(grep -E '^A2_AES_KEY=' a2.secrets.env | cut -d= -f2-)
  (( ${#chave} == 32 )) || erro "A2_AES_KEY precisa ter exatamente 32 caracteres (tem ${#chave})"
  if [[ "$I6_CAMERA_URL" == /videos/* ]]; then
    entrada_arquivo "$VIDEO_DIR/${I6_CAMERA_URL#/videos/}" "vídeo que o I6 lê" "o I6 fica tentando abrir a fonte"
  else
    ok "I6 lendo a câmera $I6_CAMERA_URL"
  fi
  entrada_arquivo "$VIDEO_DIR/$VIDEO_ARQUIVO" "vídeo do S4" "o S4 sobe sem vídeo de onde tirar o snapshot"
}

pos_subida() {
  checar_http "http://127.0.0.1:8001/docs" "API de registros do A2"
  checar_http "http://127.0.0.1:8082/" "gerador de crachás"
  ok "gerador de crachás: http://$JETSON_IP:8082/  ·  registros: http://$JETSON_IP:8001/docs"
}

testar() {
  aceite_conferir a2 i6 s4
  aceite_iniciar
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"
ods_principal "$@"
