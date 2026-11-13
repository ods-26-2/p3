#!/usr/bin/env python3
"""Teste de aceitação do A3 · Monitoramento / eventos (P3 / SIS-1).

Cadeia da 6c para o A3: P4 -> I1 -> I2 -> S1 -> (S2) -> A3 -> S3.
O S2 ainda não publica no Kafka; por isso o teste injeta o ods.s2.event que ele publicaria
(entrada simulada: S2) e confere a decisão do A3 (ods.s3.alert.command) e a resposta do S3.

Roteiro (o a3.sh faz os passos de fora):
  1. Assina os tópicos e escreve PRONTO.
  2. Passo "painel": alguém abriu o painel no navegador. O motor Kafka do A3 só liga quando
     o Streamlit roda o script, e isso só acontece com uma sessão aberta.
  3. Injeta um evento qualificado de permanência e espera o alerta do A3 no S3.
  4. Passo "video": o P4 tocou VIDEO_DIR/cam0.mp4; confere a cadeia da sessão até o S1.
"""

import os
import sys
import time
import uuid

sys.path.insert(0, "/comum")
from ods_aceite import (BLOQUEADO, FALHOU, PASSOU, AVISO, Barramento, Teste, envelope, pausa,  # noqa: E402
                        esperar_passo, http, iso, payload, pronto)

PAINEL = os.environ.get("A3_PAINEL", "http://a3:8501")
FONTE = os.environ.get("VIDEO_SOURCE_ID", "file_cam0")
ZONA = os.environ.get("ZONA_TESTE", "zona-proibida")
CADEIA = ("ods.i1.detections", "ods.i2.tracks", "ods.s1.position", "ods.s1.zone_transition", "ods.s1.zone_occupancy")


def evento_s2(min_ms: int, duracao_ms: int) -> dict:
    sessao = str(uuid.uuid4())
    return envelope("ods.s2.event", "event", "S2", {
        "event_id": str(uuid.uuid4()), "event_type": "DWELL_EXCEEDED", "rule_id": "a3-aceite-p3",
        "status": "CONFIRMED", "phase": "STARTED", "confidence": 0.92,
        "entity_id": f"e-aceite-{sessao[:4]}", "class": "person", "zone_id": ZONA,
        "started_at": iso(), "duration_ms": duracao_ms, "source_ids": [FONTE],
        "details": {"min_duration_ms": min_ms, "dwell_s": duracao_ms // 1000},
    }, captured_at=iso(), source_id=FONTE, session_id=sessao, sequence=0, artifact_version="rules-a3-aceite")


def main() -> int:
    t = Teste("a3", "S2 simulado -> A3 -> S3, e a cadeia P4 -> I1 -> I2 -> S1 pelo vídeo")
    bus = Barramento("A3")
    pronto(bus, ["ods.session.started", *CADEIA, "ods.s2.event", "ods.s3.alert.command",
                 "ods.s3.alert.reply", "ods.s3.alert", "ods.s3.alerts.reply"], "observador do A3")

    codigo, _ = http("GET", f"{PAINEL}/_stcore/health")
    t.registrar("C01", "Painel do A3 no ar (Streamlit /_stcore/health)", PASSOU if codigo == 200 else FALHOU,
                f"HTTP {codigo}")

    # Decisão do A3 sobre um evento do S2 --------------------------------------------
    if not esperar_passo(bus, "painel", 600):
        t.registrar("C02", "Painel aberto no navegador", FALHOU, "o passo painel não chegou em 10 min")
    comandos = []
    eventos = []
    for tentativa in range(2):
        pausa(10)  # o consumidor do A3 precisa receber a partição depois que o painel abre
        ev = evento_s2(min_ms=5000, duracao_ms=12000)
        eventos.append(ev)
        bus.publicar(ev)
        comandos = bus.esperar(lambda: [m for m in bus.mensagens("ods.s3.alert.command")
                                        if m.get("producer") == "A3"
                                        and str(ev["payload"]["entity_id"]) in str(payload(m).get("message", ""))], 30) or []
        if comandos:
            break
    if comandos:
        p = payload(comandos[0])
        t.registrar("C02", "A3 decide e pede alerta ao S3 (entrada simulada: S2)", PASSOU,
                    f"severidade {p.get('severity')}, \"{p.get('title')}\"")
    else:
        t.registrar("C02", "A3 decide e pede alerta ao S3 (entrada simulada: S2)", FALHOU,
                    "nenhum ods.s3.alert.command do A3 em 2 tentativas — o painel estava aberto?")
    mids = {m.get("message_id") for m in comandos}
    resp = bus.esperar(lambda: [m for m in bus.mensagens("ods.s3.alert.reply") if m.get("correlation_id") in mids], 20) or []
    oks = [m for m in resp if payload(m).get("status") == "OK"]
    if not comandos:
        t.registrar("C03", "S3 aceita o comando (ods.s3.alert.reply)", BLOQUEADO, "sem comando do A3")
    else:
        t.registrar("C03", "S3 aceita o comando (ods.s3.alert.reply)", PASSOU if oks else FALHOU,
                    f"alert_id {payload(oks[0]).get('alert_id')}" if oks else
                    (str(payload(resp[0]).get("error")) if resp else "sem resposta"))
    alerta_id = payload(oks[0]).get("alert_id") if oks else None
    alertas = bus.esperar(lambda: [m for m in bus.mensagens("ods.s3.alert") if payload(m).get("alert_id") == alerta_id], 20) \
        if alerta_id else []
    if alerta_id:
        t.registrar("C04", "Alerta publicado pelo S3 (ods.s3.alert)", PASSOU if alertas else FALHOU,
                    f"estado {payload(alertas[0]).get('state')}" if alertas else "não publicado")
        _, hist = bus.pedir("ods.s3.alerts.query", "S3", {"limit": 50}, ["ods.s3.alerts.reply"])
        achou = hist and any(a.get("alert_id") == alerta_id for a in payload(hist[0][1]).get("alerts", []))
        t.registrar("C05", "Histórico do S3 contém o alerta (ods.s3.alerts.query)",
                    PASSOU if achou else FALHOU, "" if hist else "sem resposta")

    # Cadeia pelo vídeo --------------------------------------------------------------
    if not esperar_passo(bus, "video", 900):
        t.registrar("C06", "Sessão do vídeo (ods.session.started)", FALHOU, "o passo video não terminou")
        sessao = None
    else:
        ses = bus.esperar(lambda: [m for m in bus.mensagens("ods.session.started")
                                   if m.get("source_id") == FONTE or FONTE in (payload(m).get("sources") or [])], 15) or []
        sessao = ses[-1].get("session_id") if ses else None
        t.registrar("C06", "Sessão do vídeo (ods.session.started do P4)", PASSOU if sessao else FALHOU, sessao or "")
    if sessao:
        bus.esperar(lambda: False, 20)  # deixa o fim da cadeia chegar
        for cod, top in zip(("C07", "C08", "C09", "C10"), CADEIA[:4]):
            n = len(bus.mensagens(top, lambda m: m.get("session_id") == sessao))
            estado = PASSOU if n else (AVISO if top == "ods.s1.zone_transition" else FALHOU)
            t.registrar(cod, f"{top} na sessão", estado, f"{n} mensagem(ns)")
    t.registrar("C11", "Eventos qualificados do S2 a partir da cadeia", BLOQUEADO, "o S2 ainda não publica no Kafka")
    t.registrar("C12", "Detecção de pessoas", AVISO,
                "o I1 usa o modelo de placas (não há modelo de pessoas publicado pelo B5/MOD-1)")

    injetados = {e["message_id"] for e in eventos}

    def deste_teste(topico: str, m: dict) -> bool:
        if topico == "ods.s3.alert.command":
            return m.get("message_id") in mids
        if topico in ("ods.s3.alert.reply",):
            return m.get("correlation_id") in mids
        if topico == "ods.s3.alert":
            return alerta_id is not None and payload(m).get("alert_id") == alerta_id
        if topico == "ods.s2.event":
            return False  # injetado pelo teste
        return sessao is not None and m.get("session_id") == sessao

    t.validar_contratos("C13", bus, incluir=deste_teste, produtores={"ods.s3.alert.command": "A3"})
    t.extras["eventos_s2_injetados"] = sorted(injetados)
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
