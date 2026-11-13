#!/usr/bin/env python3
"""Teste de aceitação do A5 · EPI / segurança (P3 / SIS-1).

Cadeia da 6c: P4 -> I1 -> I9 -> S2 -> S3 -> A5, com S4 gravando a evidência do evento.
O S2 ainda não publica no Kafka e não há modelo de EPI para o I1. O teste injeta:
  - um ods.s2.event PPE_NON_COMPLIANT (entrada simulada: S2), para exercitar
    S3 (ROUTING routing-a5-1) -> ods.s3.alert -> A5, a gravação automática do S4 e o
    reconhecimento do alerta pela API do A5 (A5 -> ods.s3.alert_action.command -> S3);
  - um ods.i1.detections com pessoa, capacete e colete (entrada simulada: I1), para ver o I9
    publicar ods.i9.ppe_compliance (só se a cadeia estiver de pé: ./a5.sh cadeia).
"""

import os
import sys
import uuid

sys.path.insert(0, "/comum")
from ods_aceite import (AVISO, BLOQUEADO, FALHOU, PASSOU, Barramento, Teste, envelope,  # noqa: E402
                        http, iso, payload, pronto)

API = os.environ.get("A5_API", "http://a5-backend:8000")
SENHA = os.environ["A5_ADMIN_SENHA"]
FONTE = os.environ.get("VIDEO_SOURCE_ID", "file_cam0")
ZONA, EPI = "galpao-solda", "luva"


def main() -> int:
    t = Teste("a5", "S2 simulado -> S3 -> A5 (+ S4 automático e reconhecimento), I1 simulado -> I9")
    bus = Barramento("A5-ACEITE")
    pronto(bus, ["ods.s2.event", "ods.s3.alert", "ods.s3.alert_action.command", "ods.s3.alert_action.reply",
                 "ods.s4.clip", "ods.i1.detections", "ods.i9.ppe_compliance"], "observador do A5")

    codigo, sessao_login = http("POST", f"{API}/auth/login", {"id": "administrador", "senha": SENHA})
    token = sessao_login.get("token") if codigo == 200 and isinstance(sessao_login, dict) else None
    t.registrar("C01", "Login do administrador na API do A5", PASSOU if token else FALHOU, f"HTTP {codigo}")
    aut = {"Authorization": f"Bearer {token}"} if token else {}

    # S2 simulado -> S3 -> A5 ----------------------------------------------------------
    sessao, event_id = str(uuid.uuid4()), str(uuid.uuid4())
    ev = envelope("ods.s2.event", "event", "S2", {
        "event_id": event_id, "event_type": "PPE_NON_COMPLIANT", "rule_id": "a5-luva-galpao",
        "status": "CONFIRMED", "phase": "STARTED", "confidence": 0.9, "entity_id": "e-aceite-a5",
        "class": "person", "zone_id": ZONA, "equipment_item": EPI, "started_at": iso(),
        "duration_ms": 8000, "source_ids": [FONTE], "details": {"compliance": "ABSENT", "min_duration_ms": 5000},
    }, captured_at=iso(), source_id=FONTE, session_id=sessao, sequence=0, artifact_version="rules-a5-aceite")
    bus.publicar(ev)

    alertas = bus.esperar(lambda: [m for m in bus.mensagens("ods.s3.alert") if payload(m).get("event_id") == event_id], 30) or []
    alert_id = payload(alertas[0]).get("alert_id") if alertas else None
    t.registrar("C02", "S3 cria o alerta pelo ROUTING do A5 (entrada simulada: S2)", PASSOU if alertas else FALHOU,
                f"{alert_id}, severidade {payload(alertas[0]).get('severity')}" if alertas else "nenhum ods.s3.alert do evento")

    clipes = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.clip") if payload(m).get("event_id") == event_id], 45) or []
    t.registrar("C03", "S4 grava a evidência do evento automaticamente (ods.s4.clip)", PASSOU if clipes else FALHOU,
                f"clip {payload(clipes[0]).get('clip_id')}" if clipes else
                "sem clipe do evento (o S4 tem o vídeo cam0.mp4 no buffer?)")
    if alertas:
        com_clipe = bus.esperar(lambda: [m for m in bus.mensagens("ods.s3.alert")
                                         if payload(m).get("alert_id") == alert_id and payload(m).get("clip_id")], 20)
        t.registrar("C04", "Alerta com a evidência vinculada (clip_id)", PASSOU if com_clipe else AVISO,
                    "" if com_clipe else "o S3 não vinculou o clipe ao alerta")

    no_a5 = []
    if alert_id and token:
        no_a5 = bus.esperar(lambda: [a for a in (http("GET", f"{API}/alertas", None, aut)[1] or [])
                                     if isinstance(a, dict) and a.get("alerta_id") == alert_id], 30) or []
        t.registrar("C05", "Alerta aparece no A5 (/alertas)", PASSOU if no_a5 else FALHOU,
                    f"{no_a5[0].get('titulo')} — estado {no_a5[0].get('estado')}" if no_a5 else "não listado")
    if no_a5:
        codigo, corpo = http("POST", f"{API}/alertas/{alert_id}/ack", {}, aut, timeout=40)
        acoes = bus.esperar(lambda: [m for m in bus.mensagens("ods.s3.alert_action.command")
                                     if m.get("producer") == "A5" and payload(m).get("alert_id") == alert_id], 15) or []
        t.registrar("C06", "Reconhecimento pela API do A5 vira comando ao S3", PASSOU if codigo == 200 and acoes else FALHOU,
                    f"HTTP {codigo}, {len(acoes)} comando(s)" + ("" if codigo == 200 else f": {str(corpo)[:100]}"))
        reconhecido = bus.esperar(lambda: [m for m in bus.mensagens("ods.s3.alert")
                                           if payload(m).get("alert_id") == alert_id
                                           and payload(m).get("state") == "ACKNOWLEDGED"], 20)
        t.registrar("C07", "S3 republica o alerta como ACKNOWLEDGED", PASSOU if reconhecido else FALHOU)

    # I1 simulado -> I9 -------------------------------------------------------------------
    sessao_i1 = str(uuid.uuid4())
    det = envelope("ods.i1.detections", "event", "I1", {
        "frame_index": 0, "image_width": 1280, "image_height": 720, "detections": [
            {"detection_id": 0, "class": "pessoa", "confidence": 0.94, "bbox": [412, 180, 598, 702]},
            {"detection_id": 1, "class": "capacete", "confidence": 0.96, "bbox": [450, 182, 540, 255]},
            {"detection_id": 2, "class": "colete", "confidence": 0.93, "bbox": [425, 290, 585, 510]}]},
        captured_at=iso(), source_id=FONTE, session_id=sessao_i1, sequence=0, artifact_version="app-epi-aceite")
    bus.publicar(det)
    epi = bus.esperar(lambda: [m for m in bus.mensagens("ods.i9.ppe_compliance") if m.get("session_id") == sessao_i1], 30) or []
    if epi:
        itens = {i.get("equipment_item"): i.get("compliance") for i in payload(epi[0]).get("items", [])}
        t.registrar("C08", "I9 avalia o EPI da pessoa (entrada simulada: I1)", PASSOU, str(itens))
    else:
        t.registrar("C08", "I9 avalia o EPI da pessoa (entrada simulada: I1)", AVISO,
                    "sem ods.i9.ppe_compliance: a cadeia está de pé (./a5.sh cadeia)? O I9 pode esperar o "
                    "PPE_CATALOG do A5 em ods.artifact.published")
    t.registrar("C09", "Eventos de EPI do S2 a partir do I9", BLOQUEADO, "o S2 ainda não publica no Kafka")
    t.registrar("C10", "Detecção real de EPI no vídeo", BLOQUEADO, "não há modelo de EPI publicado pelo B5/MOD-1")

    def deste_teste(topico: str, m: dict) -> bool:
        if topico == "ods.s3.alert":
            return payload(m).get("event_id") == event_id or payload(m).get("alert_id") == alert_id
        if topico == "ods.s4.clip":
            return payload(m).get("event_id") == event_id
        if topico == "ods.i9.ppe_compliance":
            return m.get("session_id") == sessao_i1
        return False

    t.validar_contratos("C11", bus, incluir=deste_teste)
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
