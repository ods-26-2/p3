"""ritmo_video.py — P3 / SIS-1: roda o script de uma inferência lendo vídeo no ritmo do próprio vídeo.

Uso (dentro da imagem da inferência):

    python ritmo_video.py <script.py> [argumentos do script…]

As inferências em modo arquivo (ex.: o I6 em I6_TEST_MODE) leem o vídeo o mais rápido que conseguem
e carimbam captured_at com a hora da leitura: um vídeo de 30 s vira uma rajada de poucos segundos.
Para o vídeo fazer o papel de câmera, cada cv2.VideoCapture.read() espera o instante do quadro no
vídeo (fps do próprio arquivo). Um VideoCapture novo (o script reabre o vídeo no fim) recomeça o relógio.

Não altera o código da equipe: troca só cv2.VideoCapture por um invólucro com o mesmo comportamento
(os scripts chamam cv2.VideoCapture(...) na hora do uso) e executa o script como __main__.
Com RITMO_VIDEO=nao, o script roda puro. Mesmo mecanismo do builds/inf_a8/i7_continuo.py.
"""
import os
import runpy
import sys
import time

import cv2

if len(sys.argv) < 2:
    sys.exit("uso: ritmo_video.py <script.py> [argumentos…]")
SCRIPT = os.path.abspath(sys.argv[1])

if os.environ.get("RITMO_VIDEO", "sim").lower() == "sim":
    _VideoCaptureOriginal = cv2.VideoCapture

    class VideoNoRitmo:
        """cv2.VideoCapture que, a cada read(), espera o instante do quadro no vídeo."""

        def __init__(self, *args, **kwargs):
            self._video = _VideoCaptureOriginal(*args, **kwargs)
            fps = self._video.get(cv2.CAP_PROP_FPS) or 0.0
            self._fps = fps if fps > 0 and fps == fps else 30.0
            self._inicio = None

        def __getattr__(self, nome):
            return getattr(self._video, nome)

        def read(self, *args):
            resultado = self._video.read(*args)
            quadros = self._video.get(cv2.CAP_PROP_POS_FRAMES)   # quadros já consumidos
            agora = time.monotonic()
            if self._inicio is None:
                self._inicio = agora - quadros / self._fps
            espera = self._inicio + quadros / self._fps - agora
            if espera > 0:
                time.sleep(espera)
            return resultado

    cv2.VideoCapture = VideoNoRitmo
    print(f"[P3] {os.path.basename(SCRIPT)} no ritmo do vídeo (RITMO_VIDEO=sim)", flush=True)

sys.path.insert(0, os.path.dirname(SCRIPT))
sys.argv = [SCRIPT] + sys.argv[2:]
runpy.run_path(SCRIPT, run_name="__main__")
