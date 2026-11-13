#!/usr/bin/env bash
# a5.sh — monta e sobe a build do A5 · EPI / segurança (VER-3) na Jetson (P3 / SIS-1).
#
#   ./a5.sh                o mesmo que ./a5.sh subir
#   ./a5.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a5.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a5.sh cadeia         sobe também I9, I2 e S1 (perfil "cadeia")
#   ./a5.sh video          sobe a cadeia e toca VIDEO_DIR/cam0.mp4 pelo P4 + I1
#   ./a5.sh status         containers, disco e Kafka da turma
#   ./a5.sh parar          derruba a build (mantém banco do A5, histórico do S3 e clipes)
#   ./a5.sh testar         teste de aceitação → resultados/aceite-a5-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a5
SEGREDOS=(A5_ADMIN_SENHA)
ETAPAS=("s4 aceite" "a5-backend s3 i9 i2 s1 p4" "a5-frontend" "i1")

checar_entradas() {
  entrada_arquivo "$VIDEO_DIR/cam0.mp4" "vídeo da cadeia" "o S4 e o P4 ficam sem vídeo"
  [[ "$I1_ONNX" == /app/I1/artifacts/app-plates/* ]] \
    && aviso "I1 com o modelo de placas (não há modelo de EPI publicado): a cadeia prova o transporte, não o domínio"
  return 0
}

pos_subida() {
  checar_http "http://127.0.0.1:8095/" "interface do A5"
  checar_http "http://127.0.0.1:8095/health" "API do A5 (pelo nginx)"
  ok "interface do A5: http://$JETSON_IP:8095  (usuário administrador; senha em a5.secrets.env)"
}

testar() {
  aceite_conferir a5-backend s3 s4
  etapa "Cadeia de EPI (I9, I2, S1)"
  dc --profile cadeia up -d i9 i2 s1 >/dev/null
  aceite_iniciar
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

case "${1:-}" in
  cadeia) dc --profile cadeia up -d i9 i2 s1 ;;
  video)  dc --profile cadeia up -d i9 i2 s1 && dc --profile cadeia --profile video up -d --force-recreate p4 i1 ;;
  *)      ods_principal "$@" ;;
esac
