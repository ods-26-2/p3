#!/usr/bin/env python3
"""Extrai quadros de um vídeo para o I7 ler (P3 / SIS-1, build do A8).

O I7 (main a4da4b0) só lê uma pasta de imagens; ele ainda não lê a câmera nem o P4.
Para usar o vídeo da cadeia (VIDEO_DIR/cam0.mp4) como entrada do I7, este script grava
I7_QUADROS_FPS quadros por segundo de vídeo em /quadros, que o I7 então processa em ordem.
Roda dentro da imagem do próprio I7 (que já tem OpenCV); nada do código do VER-5 muda.

Variáveis: I7_VIDEO (arquivo dentro de /videos), I7_QUADROS_FPS (padrão 2),
I7_QUADROS_MAX (0 = sem limite). A pasta /quadros é esvaziada antes.
"""

import os
import sys
from pathlib import Path

import cv2

VIDEO = Path(os.environ.get("I7_VIDEO_DIR", "/videos")) / os.environ.get("I7_VIDEO", "cam0.mp4")
SAIDA = Path(os.environ.get("I7_QUADROS_DIR", "/quadros"))
FPS_ALVO = float(os.environ.get("I7_QUADROS_FPS", "2") or 2)
MAXIMO = int(os.environ.get("I7_QUADROS_MAX", "0") or 0)


def main() -> int:
    if not VIDEO.is_file():
        print(f"[QUADROS] vídeo não encontrado: {VIDEO}", file=sys.stderr)
        return 1
    cap = cv2.VideoCapture(str(VIDEO))
    if not cap.isOpened():
        print(f"[QUADROS] o OpenCV não abriu {VIDEO} (codec?)", file=sys.stderr)
        return 1
    fps = cap.get(cv2.CAP_PROP_FPS) or 0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    largura = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    altura = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    duracao = total / fps if fps else 0
    print(f"[QUADROS] {VIDEO.name}: {largura}x{altura}, {fps:.1f} fps, {total} quadros, {duracao:.1f} s")

    SAIDA.mkdir(parents=True, exist_ok=True)
    for antigo in SAIDA.glob("quadro_*.jpg"):
        antigo.unlink()

    passo = max(1, round(fps / FPS_ALVO)) if fps else 1
    lidos = gravados = 0
    while True:
        ok, quadro = cap.read()
        if not ok:
            break
        if lidos % passo == 0:
            # O nome leva o instante no vídeo, para achar o quadro depois (ex.: 00012.5s)
            t = lidos / fps if fps else lidos
            cv2.imwrite(str(SAIDA / f"quadro_{gravados:05d}_{t:07.1f}s.jpg"), quadro)
            gravados += 1
            if MAXIMO and gravados >= MAXIMO:
                break
        lidos += 1
    cap.release()
    print(f"[QUADROS] {gravados} quadro(s) gravado(s) em {SAIDA} (1 a cada {passo} do vídeo)")
    return 0 if gravados else 1


if __name__ == "__main__":
    sys.exit(main())
