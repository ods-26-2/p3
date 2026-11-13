#!/usr/bin/env bash
# a3.sh — monta e sobe a build do A3 · Monitoramento / eventos (VER-6) na Jetson (P3 / SIS-1).
#
#   ./a3.sh                o mesmo que ./a3.sh subir
#   ./a3.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a3.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a3.sh video          toca VIDEO_DIR/cam0.mp4 pelo P4 e o I1 detecta (cadeia até o S1)
#   ./a3.sh cadeia         sobe também S4 e S5 (perfil "cadeia")
#   ./a3.sh status         containers, disco e Kafka da turma
#   ./a3.sh parar          derruba a build (mantém o histórico do S3)
#   ./a3.sh testar         teste de aceitação → resultados/aceite-a3-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a3
SEGREDOS=()
ETAPAS=("s3 i2 s1 a3 aceite" "p4" "i1")

checar_entradas() {
  entrada_arquivo "$VIDEO_DIR/cam0.mp4" "vídeo da cadeia" "a cadeia sobe, mas não há vídeo para o P4 tocar"
  [[ "$I1_ONNX" == /app/I1/artifacts/app-plates/* ]] \
    && aviso "I1 com o modelo de placas (não há modelo de pessoas publicado): a cadeia prova o transporte, não o domínio"
  return 0
}

pos_subida() {
  checar_http "http://127.0.0.1:8501/" "painel do A3"
  ok "painel do A3: http://$JETSON_IP:8501"
  echo "Para tocar o vídeo da cadeia: ./a3.sh video"
}

testar() {
  aceite_conferir a3 s3 i2 s1
  [[ -f "$VIDEO_DIR/cam0.mp4" ]] || erro "sem $VIDEO_DIR/cam0.mp4 para o P4 tocar"
  aceite_iniciar
  etapa "Abra o painel do A3 no navegador"
  echo "O motor Kafka do A3 só liga quando há uma sessão do painel aberta."
  echo "Abra http://$JETSON_IP:8501 e deixe a aba aberta até o fim do teste."
  if [[ -t 0 ]]; then read -r -p "Depois de abrir o painel, tecle Enter… " _
  else aviso "sem terminal interativo: seguindo sem esperar o navegador"; fi
  aceite_passo painel
  etapa "Vídeo: P4 tocando e I1 detectando"
  dc --profile video up -d --force-recreate p4 i1 >/dev/null
  docker wait "$(dc --profile video ps -aq p4)" >/dev/null
  ok "vídeo terminou"
  aceite_passo video
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

case "${1:-}" in
  video)  dc --profile video up -d --force-recreate p4 i1 ;;
  cadeia) dc --profile cadeia up -d s4 s5 ;;
  *)      ods_principal "$@" ;;
esac
