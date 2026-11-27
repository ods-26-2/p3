#!/usr/bin/env python3
"""Gera o vídeo de teste da build inf_a2: um QR que o A2 aceita (exemplo do P3 / SIS-1, não da VER-2).

O texto do QR vem pronto do inf_a2.sh (--texto): os 32 caracteres hexadecimais que o A2 decifra
(A2Local/LiberacaoCatraca/interpreta_codigo.py: AES-256-ECB de 16 bytes com CPF e validade). Aqui
só se desenha o QR com o OpenCV da própria imagem do I6 (opencv-contrib, cv2.QRCodeEncoder):
--segundos de vídeo a 10 quadros/s, 1280x720, com o QR de 2 s a 6 s. Com o I6 no ritmo do vídeo e em
laço, sai uma leitura por volta: uma "pessoa" na catraca a cada --segundos.

    python gerar_video_qr_a2.py /videos/a2-qr.mp4 --texto <hex> [--segundos 30]

Sobrescreve o arquivo (o inf_a2.sh só chama quando o código muda ou vence).
"""

import argparse
import os
import sys

import cv2
import numpy as np


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("saida")
    ap.add_argument("--texto", required=True)
    ap.add_argument("--segundos", type=int, default=30)
    args = ap.parse_args()
    if args.segundos < 10:
        print("[A2-video] --segundos deve ser >= 10 (o QR fica de 2 s a 6 s)", file=sys.stderr)
        return 1

    largura, altura, fps = 1280, 720, 10
    qr = cv2.QRCodeEncoder.create().encode(args.texto)
    lado = 360
    qr = cv2.resize(qr, (lado, lado), interpolation=cv2.INTER_NEAREST)
    qr = cv2.cvtColor(qr, cv2.COLOR_GRAY2BGR)

    temporario = args.saida + ".tmp.mp4"
    escritor = cv2.VideoWriter(temporario, cv2.VideoWriter_fourcc(*"mp4v"), fps, (largura, altura))
    if not escritor.isOpened():
        print("[A2-video] o OpenCV não abriu o gravador mp4v", file=sys.stderr)
        return 1
    y0, x0 = (altura - lado) // 2, (largura - lado) // 2
    for i in range(fps * args.segundos):
        quadro = np.full((altura, largura, 3), 90, dtype=np.uint8)
        if 2 * fps <= i < 6 * fps:
            cv2.rectangle(quadro, (x0 - 40, y0 - 40), (x0 + lado + 40, y0 + lado + 40), (255, 255, 255), -1)
            quadro[y0:y0 + lado, x0:x0 + lado] = qr
        cv2.putText(quadro, "P3 - catraca de teste do A2 (cam0)", (40, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.2,
                    (230, 230, 230), 2)
        escritor.write(quadro)
    escritor.release()

    conferido, _, _ = cv2.QRCodeDetector().detectAndDecode(qr)
    if conferido != args.texto:
        os.remove(temporario)
        print(f"[A2-video] o QR gerado não confere ('{conferido}')", file=sys.stderr)
        return 1
    os.replace(temporario, args.saida)
    print(f"[A2-video] {args.saida}: {args.segundos} s, QR de 2 s a 6 s (conferido)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
