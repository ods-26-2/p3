"""i7_continuo.py — P3 / SIS-1: roda o I7 (--video) no ritmo do vídeo, como se fosse uma câmera.

O I7 (development 9e24056; também a main 1441bbb, scripts/aplicacaoModelov5-fast+rodosol.py) processa um vídeo o mais rápido que
consegue e carimba captured_at com a hora da leitura. Para a build inf_a8, o vídeo faz o papel da
câmera da entrada do A8: com I7_TEMPO_REAL=sim, cada leitura de quadro espera o instante dele no
vídeo (fps do próprio arquivo), e os carros chegam ao A8 no tempo do vídeo, sem rajada.

Não altera o código do I7: troca só cv2.VideoCapture por um invólucro com o mesmo comportamento
(o I7 chama cv2.VideoCapture(...) na hora do uso) e executa o script dele como __main__.
Os argumentos vão inteiros para o I7 (ex.: --video /videos/VER5.mp4).
Para desfazer: I7_TEMPO_REAL=nao (o I7 roda puro).
"""
import os
import runpy
import sys
import time

import cv2

# I7_SCRIPT só serve à simulação do P3 fora da imagem
SCRIPT = os.environ.get("I7_SCRIPT", "/app/scripts/aplicacaoModelov5-fast+rodosol.py")

if os.environ.get("I7_TEMPO_REAL", "sim").lower() == "sim":
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
            quadros = self._video.get(cv2.CAP_PROP_POS_FRAMES)   # quadros já consumidos (grab + read)
            agora = time.monotonic()
            if self._inicio is None:
                self._inicio = agora - quadros / self._fps
            espera = self._inicio + quadros / self._fps - agora
            if espera > 0:
                time.sleep(espera)
            return resultado

    cv2.VideoCapture = VideoNoRitmo
    print("[P3] I7 no ritmo do vídeo (I7_TEMPO_REAL=sim)", flush=True)

# O script do I7 importa os módulos vizinhos (detector_p2, publicador_eventos, fonte_p4)
sys.path.insert(0, os.path.dirname(SCRIPT))
sys.argv = [SCRIPT] + sys.argv[1:]
runpy.run_path(SCRIPT, run_name="__main__")
