#!/usr/bin/env python3
"""Gera um vídeo de exemplo com um QR code para o I6 (exemplo do P3 / SIS-1, não da VER-2).

Nenhum repositório traz um vídeo com QR. Este script desenha o QR "ODS-INF-P3" com o OpenCV da
própria imagem do I6 (opencv-contrib, cv2.QRCodeEncoder): 20 s a 10 quadros/s, 1280x720, o QR
aparece de 2 s a 6 s. O I6 relê o vídeo em laço, então publica uma leitura por volta (o QR some
por 14 s, mais que o I6_QR_LOST_SECONDS de 3 s).

    python gerar_video_qr.py /videos/inf-qr.mp4 [--texto ODS-INF-P3]

Não sobrescreve um arquivo que já existe.
"""

import argparse
import os
import sys

import cv2
import numpy as np


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("saida")
    ap.add_argument("--texto", default="ODS-INF-P3")
    args = ap.parse_args()

    if os.path.exists(args.saida):
        print(f"[I6-video] {args.saida} já existe; mantido")
        return 0

    largura, altura, fps, segundos = 1280, 720, 10, 20
    qr = cv2.QRCodeEncoder.create().encode(args.texto)
    lado = 360
    qr = cv2.resize(qr, (lado, lado), interpolation=cv2.INTER_NEAREST)
    qr = cv2.cvtColor(qr, cv2.COLOR_GRAY2BGR)

    temporario = args.saida + ".tmp.mp4"
    escritor = cv2.VideoWriter(temporario, cv2.VideoWriter_fourcc(*"mp4v"), fps, (largura, altura))
    if not escritor.isOpened():
        print("[I6-video] o OpenCV não abriu o gravador mp4v", file=sys.stderr)
        return 1
    y0, x0 = (altura - lado) // 2, (largura - lado) // 2
    for i in range(fps * segundos):
        quadro = np.full((altura, largura, 3), 90, dtype=np.uint8)
        if 2 * fps <= i < 6 * fps:
            # margem branca (zona de silêncio) em volta do QR
            cv2.rectangle(quadro, (x0 - 40, y0 - 40), (x0 + lado + 40, y0 + lado + 40), (255, 255, 255), -1)
            quadro[y0:y0 + lado, x0:x0 + lado] = qr
        cv2.putText(quadro, "P3 - exemplo para o I6", (40, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (230, 230, 230), 2)
        escritor.write(quadro)
    escritor.release()

    conferido, _, _ = cv2.QRCodeDetector().detectAndDecode(qr)
    os.replace(temporario, args.saida)
    print(f"[I6-video] {args.saida}: {segundos} s, QR '{args.texto}' de 2 s a 6 s (conferido: '{conferido}')")
    return 0


if __name__ == "__main__":
    sys.exit(main())
