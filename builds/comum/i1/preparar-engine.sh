#!/bin/sh
# preparar-engine.sh — garante a engine TensorRT de um pacote B5 para o I1 (P3 / SIS-1).
# Roda DENTRO da imagem ods-i1-gpu (Dockerfile.jetson do I1), com runtime nvidia.
#
#   preparar-engine.sh <pasta do pacote com metadata.json> [precisões]   (padrão: FP16)
#
# Se a engine já está em $P2_ENGINE_DIR/<artifact_id>-<artifact_version> e carrega com o
# TensorRT desta imagem, não faz nada (segundos). Senão (ausente, corrompida ou compilada com
# outro TensorRT), compila de novo com p2-build --force (minutos, só na primeira vez).
# Usado pelo serviço i1-engine do compose e por validacao/i1/testar-i1-gpu.sh.
set -eu

PACOTE=${1:?uso: preparar-engine.sh <pasta do pacote B5> [precisões]}
shift
PRECISOES=${*:-FP16}
: "${P2_ENGINE_DIR:?defina P2_ENGINE_DIR}"
# Sem isto o P2 cairia para a CPU (ONNX Runtime) sem avisar.
export P2_BACKEND=trt

REF=$(python3 -c 'import json, sys
m = json.load(open(sys.argv[1] + "/metadata.json"))
print(m["artifact_id"] + "-" + m["artifact_version"])' "$PACOTE")

if python3 - "$REF" "$PRECISOES" <<'PY'
import sys
import p2
ref, precisoes = sys.argv[1], sys.argv[2].split()
try:
    for prec in precisoes:
        p2.release(p2.load(ref, {"precision": prec}))
except Exception as err:
    print(f"[engine] {ref} precisa ser compilado: {err}")
    sys.exit(1)
PY
then
  echo "[engine] $REF ($PRECISOES) já está em $P2_ENGINE_DIR e carrega com este TensorRT"
  exit 0
fi

echo "[engine] compilando $REF ($PRECISOES) em $P2_ENGINE_DIR; leva alguns minutos na primeira vez"
# shellcheck disable=SC2086
p2-build "$PACOTE" --precision $PRECISOES --force
echo "[engine] $REF pronto"
