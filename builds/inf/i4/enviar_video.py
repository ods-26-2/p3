#!/usr/bin/env python3
"""Manda um vídeo ao servidor de quadros do I4, como o webcam.py do I4 faz com a câmera (P3 / SIS-1).

O webcam.py da equipe (INV-2) só abre câmera por índice. Este script faz o mesmo envio a partir
de um arquivo: cada quadro vira um JPEG numa mensagem binária em ws://<host>:18080/ws/video, no
ritmo de --fps (o servidor processa em série e o modelo foi treinado a 25 quadros/s). Sem espelhar
a imagem, como no webcam.py.

O servidor aceita uma conexão por vez: com uma webcam conectada, este envio é recusado.

    python enviar_video.py video.mp4 --url ws://i4-server:18080/ws/video --fps 25 [--voltas 1]
"""

import argparse
import sys
import time

import cv2
from websockets.sync.client import connect


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("video")
    ap.add_argument("--url", default="ws://i4-server:18080/ws/video")
    ap.add_argument("--fps", type=float, default=25.0)
    ap.add_argument("--quality", type=int, default=85, help="qualidade JPEG (a do webcam.py)")
    ap.add_argument("--voltas", type=int, default=1, help="quantas vezes tocar o vídeo")
    ap.add_argument("--espera", type=float, default=60.0, help="s esperando o servidor aceitar")
    args = ap.parse_args()

    cap = cv2.VideoCapture(args.video)
    if not cap.isOpened():
        print(f"[I4-video] não abri {args.video}", file=sys.stderr)
        return 2
    w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"[I4-video] {args.video}: {w}x{h}, {cap.get(cv2.CAP_PROP_FRAME_COUNT):.0f} quadros")

    limite = time.monotonic() + args.espera
    while True:
        try:
            ws = connect(args.url, max_size=None, open_timeout=5)
            break
        except OSError as e:
            if time.monotonic() > limite:
                print(f"[I4-video] o servidor não aceitou em {args.espera:.0f} s: {e}", file=sys.stderr)
                return 1
            time.sleep(2)

    params = [cv2.IMWRITE_JPEG_QUALITY, args.quality]
    intervalo = 1.0 / args.fps
    n = 0
    with ws:
        print(f"[I4-video] conectado em {args.url}; enviando a {args.fps:g} quadros/s")
        for volta in range(args.voltas):
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            proximo = time.monotonic()
            while True:
                ok, bgr = cap.read()
                if not ok:
                    break
                espera = proximo - time.monotonic()
                if espera > 0:
                    time.sleep(espera)
                proximo += intervalo
                ok, jpg = cv2.imencode(".jpg", bgr, params)
                if ok:
                    ws.send(jpg.tobytes())
                    n += 1
        # Pausa sem quadros: o I4 fecha o sinal depois de --gap (1 s) sem quadro novo.
        time.sleep(2)
    cap.release()
    print(f"[I4-video] {n} quadros enviados")
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main())
