#!/usr/bin/env bash

# Validação de hardware NVIDIA Jetson
# Uso:
# ./validar-hardware-jetson.sh <container>

N="${1:?Uso: $0 <nome-container>}"
F=0

ok()  { echo "[OK]    $1"; }
ko()  { echo "[FALHA] $1"; F=$((F+1)); }
av()  { echo "[AVISO] $1"; }

echo "========================================"
echo " VALIDACAO HARDWARE NVIDIA JETSON"
echo "========================================"

# 1. Arquitetura
ARCH=$(uname -m)

if [ "$ARCH" = "aarch64" ]; then
    ok "Arquitetura ARM64"
else
    ko "Arquitetura inesperada: $ARCH"
fi

# 2. Identificação Jetson
if [ -f /etc/nv_tegra_release ]; then
    ok "Sistema NVIDIA L4T identificado"
    cat /etc/nv_tegra_release
else
    ko "Sistema L4T nao identificado"
fi

# 3. Modelo do equipamento
if [ -f /proc/device-tree/model ]; then
    MODEL=$(tr -d '\0' < /proc/device-tree/model)
    ok "Modelo: $MODEL"
else
    av "Modelo Jetson nao identificado"
fi

# 4. Dispositivo GPU
if [ -e /dev/nvhost-gpu ]; then
    ok "Dispositivo GPU encontrado"
else
    ko "Dispositivo /dev/nvhost-gpu ausente"
fi

# 5. CUDA no host
if command -v nvcc >/dev/null 2>&1; then
    nvcc --version | tail -n 1
    ok "Compilador CUDA encontrado"
elif [ -d /usr/local/cuda ]; then
    ok "Diretorio CUDA encontrado"
else
    av "CUDA nao encontrado no host"
fi

# 6. Memoria
if command -v free >/dev/null 2>&1; then
    free -h
    ok "Memoria consultada"
else
    av "Comando free indisponivel"
fi

# 7. Temperatura
if command -v tegrastats >/dev/null 2>&1; then
    ok "tegrastats disponivel"
else
    av "tegrastats nao encontrado"
fi

# 8. Container
if ! docker inspect "$N" >/dev/null 2>&1; then
    ko "Container nao encontrado: $N"
else
    STATE=$(docker inspect -f '{{.State.Status}}' "$N")

    if [ "$STATE" = "running" ]; then
        ok "Container em execucao"
    else
        ko "Container parado: $STATE"
    fi

    # 9. Arquitetura do container
    CARCH=$(docker exec "$N" uname -m 2>/dev/null)

    if [ "$CARCH" = "aarch64" ]; then
        ok "Container ARM64"
    else
        ko "Arquitetura do container: ${CARCH:-indisponivel}"
    fi

    # 10. Dispositivos NVIDIA no container
    if docker exec "$N" test -e /dev/nvhost-gpu 2>/dev/null; then
        ok "GPU visivel dentro do container"
    else
        av "GPU nao visivel dentro do container"
    fi

    # 11. Bibliotecas CUDA
    if docker exec "$N" sh -c \
        'ldconfig -p 2>/dev/null | grep -q libcudart' 2>/dev/null; then
        ok "Biblioteca CUDA Runtime encontrada"
    else
        av "CUDA Runtime nao localizado pelo ldconfig"
    fi

    # 12. TensorRT
    if docker exec "$N" sh -c \
        'ldconfig -p 2>/dev/null | grep -q libnvinfer' 2>/dev/null; then
        ok "Biblioteca TensorRT encontrada"
    else
        av "TensorRT nao localizado pelo ldconfig"
    fi
fi

echo "========================================"

if [ "$F" -eq 0 ]; then
    echo "RESULTADO: VALIDACAO BASICA APROVADA"
else
    echo "RESULTADO: $F FALHA(S)"
fi

exit "$F"
