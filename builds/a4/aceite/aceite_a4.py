#!/usr/bin/env python3
"""Teste de aceitação do A4 · Esporte / arbitragem (P3 / SIS-1).

Cadeia: I3 (calibração) -> A4;  P4 -> I1 (modelo app-volei, classe ball) -> I2 -> S1 -> A4
        A4 -> ods.p7.move.command (P7 ausente);  A4 -> ods.s4.capture.command -> S4 -> A4 (replay)

Roteiro (o a4.sh faz os passos de fora):
  1. Assina os tópicos e escreve PRONTO; cria uma partida pela API do A4.
  2. Passo "calibrar": o I3 publicou a calibração da quadra.
  3. Move a câmera pela API (comando ao P7) e confere o ods.p7.move.command.
  4. Passo "video": o P4 tocou o vídeo; confere bolas no I1/I2/S1 e no player do A4 e,
     se o A4 marcou algum lance, pede o replay (clipe do S4).
"""

import os
import sys

sys.path.insert(0, "/comum")
from ods_aceite import (AVISO, BLOQUEADO, FALHOU, PASSOU, Barramento, Teste,  # noqa: E402
                        esperar_passo, http, payload, pronto)

API = os.environ.get("A4_API", "http://a4-back:8000")
TOKEN = os.environ["A4_TOKEN"]
FONTE = os.environ.get("VIDEO_SOURCE_ID", "file_quadra")
AUT = {"Authorization": f"Bearer {TOKEN}"}
CADEIA = ("ods.i1.detections", "ods.i2.tracks", "ods.s1.position")


def main() -> int:
    t = Teste("a4", "I3 + P4 -> I1 -> I2 -> S1 -> A4, comando ao P7 e replay pelo S4")
    bus = Barramento("A4-ACEITE")
    pronto(bus, ["ods.session.started", "ods.i3.calibration", *CADEIA, "ods.p7.move.command",
                 "ods.p7.move.reply", "ods.p7.state", "ods.s4.capture.command", "ods.s4.capture.reply",
                 "ods.s4.clip"], "observador do A4")

    codigo, saude = http("GET", f"{API}/health")
    ok = codigo == 200 and isinstance(saude, dict) and saude.get("kafka_habilitado")
    t.registrar("C01", "API do A4 com Kafka ligado (/health)", PASSOU if ok else FALHOU,
                f"HTTP {codigo}, kafka_habilitado={saude.get('kafka_habilitado') if isinstance(saude, dict) else '?'}")

    codigo, partida = http("POST", f"{API}/partidas", {"time_a": "Aceite A", "time_b": "Aceite B",
                                                        "source_id": FONTE}, AUT)
    pid = partida.get("id") if codigo == 200 and isinstance(partida, dict) else None
    t.registrar("C02", "Partida criada pela API (token do árbitro)", PASSOU if pid else FALHOU,
                pid or f"HTTP {codigo}: {str(partida)[:100]}")

    # Calibração -----------------------------------------------------------------------
    if esperar_passo(bus, "calibrar", 600):
        cal = bus.esperar(lambda: [m for m in bus.mensagens("ods.i3.calibration") if m.get("source_id") == FONTE], 20) or []
        t.registrar("C03", "Calibração publicada pelo I3 (ods.i3.calibration)", PASSOU if cal else FALHOU,
                    f"{cal[-1].get('artifact_version')}, erro {payload(cal[-1]).get('reprojection_rms_cm')} cm"
                    if cal else f"nada de {FONTE}")
        def carregadas():
            _, h = http("GET", f"{API}/health")
            return FONTE in ((h.get("calibracoes_carregadas") or []) if isinstance(h, dict) else [])
        carregada = bus.esperar(carregadas, 20)
        t.registrar("C04", "A4 carregou a calibração", PASSOU if carregada else FALHOU)
    else:
        t.registrar("C03", "Calibração publicada pelo I3", FALHOU, "o passo calibrar não terminou")

    # Câmera (P7) ----------------------------------------------------------------------
    codigo, corpo = http("POST", f"{API}/camera/enquadrar?pan_deg=10&tilt_deg=-5", None, AUT)
    cmds = bus.esperar(lambda: [m for m in bus.mensagens("ods.p7.move.command") if m.get("producer") == "A4"], 15) or []
    t.registrar("C05", "A4 envia o comando de ângulo (ods.p7.move.command)", PASSOU if cmds else FALHOU,
                f"HTTP {codigo}; pan {payload(cmds[0]).get('pan_deg')} tilt {payload(cmds[0]).get('tilt_deg')}"
                if cmds else f"HTTP {codigo}: {str(corpo)[:100]}")
    mids_p7 = {m.get("message_id") for m in cmds}
    resp = bus.esperar(lambda: bus.correlacionadas(["ods.p7.move.reply"], next(iter(mids_p7), "")), 10) if cmds else []
    t.registrar("C06", "P7 responde e move o pan-tilt", PASSOU if resp else BLOQUEADO,
                "" if resp else "o P7 ainda não atende pelo Kafka (repositório só tem o driver serial)")

    # Vídeo ------------------------------------------------------------------------------
    sessao = None
    if esperar_passo(bus, "video", 1200):
        ses = bus.esperar(lambda: [m for m in bus.mensagens("ods.session.started")
                                   if m.get("source_id") == FONTE or FONTE in (payload(m).get("sources") or [])], 15) or []
        sessao = ses[-1].get("session_id") if ses else None
    t.registrar("C07", "Sessão do vídeo da quadra (ods.session.started)", PASSOU if sessao else FALHOU, sessao or "")
    if sessao:
        bus.esperar(lambda: False, 20)
        da_sessao = lambda m: m.get("session_id") == sessao  # noqa: E731
        bolas_i1 = sum(1 for m in bus.mensagens("ods.i1.detections", da_sessao)
                       for d in payload(m).get("detections", []) if d.get("class") == "ball")
        t.registrar("C08", "I1 detecta a bola (modelo app-volei)", PASSOU if bolas_i1 else FALHOU,
                    f"{bolas_i1} detecção(ões) de ball em {len(bus.mensagens('ods.i1.detections', da_sessao))} quadro(s)")
        n_i2 = len(bus.mensagens("ods.i2.tracks", da_sessao))
        t.registrar("C09", "Trilhas do I2 na sessão", PASSOU if n_i2 else FALHOU, f"{n_i2} mensagem(ns)")
        bolas_s1 = sum(1 for m in bus.mensagens("ods.s1.position", da_sessao)
                       for p in payload(m).get("positions", []) if p.get("class") == "ball")
        t.registrar("C10", "Posições de bola do S1 (o que o A4 lê)", PASSOU if bolas_s1 else FALHOU,
                    f"{bolas_s1} posição(ões)")
        codigo, det = http("GET", f"{API}/p6/deteccoes?de=0&ate=100000")
        t.registrar("C11", "Bolas no player do A4 (/p6/deteccoes)",
                    PASSOU if codigo == 200 and det else (AVISO if codigo == 200 else FALHOU),
                    f"{len(det) if isinstance(det, list) else 0} instante(s) com bola")

    # Lances e replay ----------------------------------------------------------------------
    decisoes = []
    if pid:
        _, p = http("GET", f"{API}/partidas/{pid}")
        decisoes = p.get("decisoes", []) if isinstance(p, dict) else []
    if not decisoes:
        t.registrar("C12", "Lance (quique) decidido pelo A4", AVISO,
                    "nenhum lance nesta partida: o vídeo pode não ter quique visível com a calibração usada")
    else:
        t.registrar("C12", "Lance (quique) decidido pelo A4", PASSOU,
                    f"{len(decisoes)} lance(s); último: {decisoes[-1].get('veredito')}")
        codigo, pedido = http("POST", f"{API}/decisoes/{decisoes[-1]['decisao_id']}/replay", None, AUT)
        mid = pedido.get("pedido") if isinstance(pedido, dict) else None
        clipes = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.clip") if m.get("correlation_id") == mid], 40) \
            if mid else []
        t.registrar("C13", "Replay do lance: clipe do S4 (ods.s4.capture.command -> ods.s4.clip)",
                    PASSOU if clipes else FALHOU,
                    f"clip {payload(clipes[0]).get('clip_id')}" if clipes else f"HTTP {codigo}: {str(pedido)[:100]}")

    def deste_teste(topico: str, m: dict) -> bool:
        if topico in CADEIA or topico == "ods.session.started":
            return sessao is not None and m.get("session_id") == sessao
        if topico in ("ods.p7.move.command", "ods.s4.capture.command"):
            return m.get("producer") == "A4"
        if topico == "ods.i3.calibration":
            return m.get("source_id") == FONTE
        return False

    t.validar_contratos("C14", bus, incluir=deste_teste,
                        produtores={"ods.s4.capture.command": "A4", "ods.session.started": "P4"})
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
