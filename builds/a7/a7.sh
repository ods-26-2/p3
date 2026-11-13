#!/usr/bin/env bash
# a7.sh — monta e sobe a build do A7 · Restaurante / áudio e voz (VER-4) na Jetson (P3 / SIS-1).
#
#   ./a7.sh                o mesmo que ./a7.sh subir
#   ./a7.sh subir          confere a placa, baixa o código, constrói o que falta e sobe tudo
#   ./a7.sh subir --reconstruir   reconstrói todas as imagens, mesmo as que já existem
#   ./a7.sh fala           o I5 transcreve I5_AUDIO (a7.env) e publica para o A7
#   ./a7.sh status         containers, disco e Kafka da turma
#   ./a7.sh parar          derruba a build (mantém o cache do Whisper)
#   ./a7.sh testar         teste de aceitação → resultados/aceite-a7-*.txt|json
#
# Para remover a build da placa: ./limpar.sh (veja ./limpar.sh --help)
# Variáveis opcionais: MIN_LIVRE_GB (padrão 4), ESPERA_S (padrão 300)
APP=a7
SEGREDOS=()
# O I5 (torch + transformers) é a imagem maior: sozinha e por último.
ETAPAS=("a7 aceite" "i5")

checar_entradas() {
  if [[ -d "$I5_AUDIO_DIR" ]]; then
    entrada_arquivo "$I5_AUDIO_DIR/$I5_AUDIO" "áudio do I5" "./a7.sh fala não terá o que transcrever"
  else
    aviso "a pasta $I5_AUDIO_DIR ainda não existe (o padrão é a do clone do I5, criada pelo preparar-codigo)"
  fi
  return 0
}

pos_subida() {
  checar_http "http://127.0.0.1:${A7_PORTA:-8000}/" "A7"
  ok "terminal do balcão: http://$JETSON_IP:${A7_PORTA:-8000}/  ·  gestor: /gestor  ·  métricas: /metricas"
  echo "Para o I5 transcrever um áudio e mandar ao A7: ./a7.sh fala"
}

testar() {
  aceite_conferir a7
  aceite_iniciar
  etapa "I5 transcrevendo $I5_AUDIO (Whisper em CPU; na primeira vez baixa ~1 GB)"
  dc --profile i5 run --rm i5 || aviso "o I5 terminou com erro"
  aceite_passo fala
  aceite_concluir
}

# shellcheck source=../comum/lib.sh
source "$(dirname "$(readlink -f "$0")")/../comum/lib.sh"

case "${1:-}" in
  fala) dc --profile i5 run --rm i5 ;;
  *)    ods_principal "$@" ;;
esac
