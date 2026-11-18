#!/usr/bin/env python3
"""Teste de aceitação do A5 · EPI / segurança (P3 / SIS-1).

Cadeia da 6c: P4 -> I1 -> I9 -> S2 -> S3 -> A5, com S4 gravando a evidência do evento.
O S2 ainda não publica no Kafka. O teste:
  - injeta um ods.s2.event PPE_NON_COMPLIANT (entrada simulada: S2), para exercitar
    S3 (ROUTING routing-a5-1) -> ods.s3.alert -> A5, a gravação automática do S4 e o
    reconhecimento do alerta pela API do A5 (A5 -> ods.s3.alert_action.command -> S3);
  - injeta um ods.i1.detections com pessoa, capacete e colete (entrada simulada: I1), para ver
    o I9 publicar ods.i9.ppe_compliance;
  - depois pede o vídeo (passo externo "video": o a5.sh toca VIDEO_ARQUIVO pelo P4) e mede a
    cadeia real: I1 na GPU com o modelo de EPI do B5 -> I9, e I1 -> I2 -> S1.
Os itens simulados vêm antes do vídeo porque a sessão nova do P4 esvazia o buffer do S4.
"""

import os
import sys
import uuid
from collections import Counter

sys.path.insert(0, "/comum")
from ods_aceite import (AVISO, BLOQUEADO, FALHOU, PASSOU, Barramento, Teste, envelope,  # noqa: E402
                        esperar_passo, http, iso, payload, pronto)

API = os.environ.get("A5_API", "http://a5-backend:8000")
SENHA = os.environ["A5_ADMIN_SENHA"]
FONTE = os.environ.get("VIDEO_SOURCE_ID", "file_epi")
# artifact_id-artifact_version do pacote do I1 (app-epi/1.0.0 -> app-epi-1.0.0)
PACOTE = os.environ.get("I1_PACOTE", "app-epi/1.0.0").replace("/", "-")
ZONA, EPI = "galpao-solda", "luva"
CLASSES_EPI = {"pessoa", "capacete", "colete"}


def estados_epi(msgs: list) -> Counter:
    """Conta "<equipamento>:<estado>" nas avaliações do I9 (payload.persons[].equipment[]),
    o formato que o I9 publica hoje (8ae3933)."""
    return Counter(f"{e.get('equipment_item')}:{e.get('state')}"
                   for m in msgs for p in payload(m).get("persons", []) for e in p.get("equipment", []))
# Quantas mensagens reais por tópico entram na validação de contrato (o vídeo gera milhares).
AMOSTRA_CONTRATO = 50


def main() -> int:
    t = Teste("a5", "S2 simulado -> S3 -> A5 (+ S4 automático e reconhecimento), I1 simulado -> I9, "
                    "vídeo real: P4 -> I1 (GPU, EPI) -> I9 e I2 -> S1")
    bus = Barramento("A5-ACEITE")
    pronto(bus, ["ods.s2.event", "ods.s3.alert", "ods.s3.alert_action.command", "ods.s3.alert_action.reply",
                 "ods.s4.clip", "ods.i1.detections", "ods.i9.ppe_compliance", "ods.session.started",
                 "ods.i2.tracks", "ods.s1.position", "ods.s1.zone_transition"], "observador do A5")

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
                "sem clipe do evento (o S4 tem o vídeo VIDEO_ARQUIVO no buffer?)")
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
        itens = dict(estados_epi(epi[:1]))
        t.registrar("C08", "I9 avalia o EPI da pessoa (entrada simulada: I1)",
                    PASSOU if itens else FALHOU,
                    str(itens) if itens else "avaliação sem equipamentos associados à pessoa")
    else:
        t.registrar("C08", "I9 avalia o EPI da pessoa (entrada simulada: I1)", AVISO,
                    "sem ods.i9.ppe_compliance: a cadeia está de pé (./a5.sh cadeia)? O I9 pode esperar o "
                    "PPE_CATALOG do A5 em ods.artifact.published")
    t.registrar("C09", "Eventos de EPI do S2 a partir do I9", BLOQUEADO, "o S2 ainda não publica no Kafka")

    # Vídeo real: P4 -> I1 (GPU, modelo de EPI) -> I9 · I1 -> I2 -> S1 ---------------------
    if not esperar_passo(bus, "video", 1800):
        for cod, desc in (("C10", "Detecção real de EPI no vídeo (I1 na GPU)"),
                          ("C12", "I9 avalia o EPI das pessoas do vídeo"),
                          ("C13", "Rastreio e zonas do vídeo (I2 -> S1)")):
            t.registrar(cod, desc, BLOQUEADO, "o vídeo não foi tocado (passo 'video' não chegou)")
        sessao_video = None
    else:
        bus.esperar(lambda: False, 20)  # deixa chegar o fim da cadeia (I9, I2, S1)
        sessoes = [m.get("session_id") for m in bus.mensagens("ods.session.started")
                   if m.get("source_id") == FONTE or payload(m).get("source_id") == FONTE]
        sessao_video = sessoes[-1] if sessoes else None

        def do_video(m: dict) -> bool:
            if sessao_video:
                return m.get("session_id") == sessao_video
            return m.get("source_id") == FONTE and m.get("session_id") != sessao_i1

        dets = bus.mensagens("ods.i1.detections", do_video)
        classes = Counter(d.get("class") for m in dets for d in payload(m).get("detections", []))
        versoes = sorted({str(m.get("artifact_version")) for m in dets})
        gpu = bool(versoes) and all(v.startswith(PACOTE) and v.endswith("-fp16") for v in versoes)
        detalhe = (f"{len(dets)} quadro(s), sessão {sessao_video or '?'}, classes {dict(classes)}, "
                   f"artifact_version {versoes}")
        if not dets:
            t.registrar("C10", "Detecção real de EPI no vídeo (I1 na GPU)", FALHOU,
                        f"nenhum ods.i1.detections de {FONTE} (o I1 subiu? veja logs do i1 e do i1-engine)")
        elif not gpu:
            t.registrar("C10", "Detecção real de EPI no vídeo (I1 na GPU)", FALHOU,
                        f"{detalhe}: esperado {PACOTE}-fp16 (TensorRT); o I1 caiu para a CPU ou outro modelo?")
        elif not classes.get("pessoa"):
            t.registrar("C10", "Detecção real de EPI no vídeo (I1 na GPU)", AVISO,
                        f"{detalhe}: nenhuma pessoa detectada (o vídeo tem trabalhadores?)")
        else:
            t.registrar("C10", "Detecção real de EPI no vídeo (I1 na GPU)", PASSOU, detalhe)
        t.extras["video"] = {"source_id": FONTE, "sessao": sessao_video, "quadros_i1": len(dets),
                             "classes": dict(classes), "artifact_version": versoes,
                             "classes_fora_do_modelo": sorted(set(classes) - CLASSES_EPI)}

        avals = bus.mensagens("ods.i9.ppe_compliance", do_video)
        estados = estados_epi(avals)
        if avals and not estados and classes.get("pessoa"):
            t.registrar("C12", "I9 avalia o EPI das pessoas do vídeo", AVISO,
                        f"{len(avals)} avaliação(ões), nenhuma com equipamento associado a uma pessoa")
        elif avals:
            t.registrar("C12", "I9 avalia o EPI das pessoas do vídeo", PASSOU,
                        f"{len(avals)} avaliação(ões): {dict(estados)}")
        elif classes.get("pessoa"):
            t.registrar("C12", "I9 avalia o EPI das pessoas do vídeo", FALHOU,
                        "o I1 detectou pessoas, mas o I9 não publicou ods.i9.ppe_compliance da sessão")
        else:
            t.registrar("C12", "I9 avalia o EPI das pessoas do vídeo", AVISO, "sem pessoas detectadas no vídeo")
        t.extras["video"]["i9"] = {"avaliacoes": len(avals), "estados": dict(estados)}

        trilhas = bus.mensagens("ods.i2.tracks", do_video)
        posicoes = bus.mensagens("ods.s1.position", do_video)
        transicoes = bus.mensagens("ods.s1.zone_transition", do_video)
        no_galpao = [m for m in transicoes if payload(m).get("zone_id") == ZONA]
        # Mensagem vazia (tracks/positions = []) não prova rastreio: conta só as com conteúdo.
        com_trilha = [m for m in trilhas if payload(m).get("tracks")]
        com_posicao = [m for m in posicoes if payload(m).get("positions")]
        detalhe = (f"I2 {len(trilhas)} ({len(com_trilha)} com trilhas), S1 posições {len(posicoes)} "
                   f"({len(com_posicao)} com posições), transições {len(transicoes)} ({len(no_galpao)} em "
                   f"{ZONA}); zonas de exemplo do P3, em pixels")
        if com_trilha and com_posicao:
            estado = PASSOU
        elif trilhas or posicoes:
            estado = AVISO
            detalhe += ("; I2/S1 publicam, mas sem trilhas" if not com_trilha else "; trilhas sem posição no S1")
        else:
            estado = AVISO if dets else FALHOU
        t.registrar("C13", "Rastreio e zonas do vídeo (I2 -> S1)", estado, detalhe)

        # Resolução do vídeo e uma mensagem real de cada elo (para diagnóstico no .json).
        tamanhos = Counter(f"{payload(m).get('image_width')}x{payload(m).get('image_height')}" for m in dets)
        t.extras["video"]["resolucao"] = dict(tamanhos)
        t.extras["video"]["amostras_reais"] = {
            "ods.i1.detections": next((m for m in dets if payload(m).get("detections")), dets[0] if dets else None),
            "ods.i9.ppe_compliance": next((m for m in avals if payload(m).get("persons")), avals[0] if avals else None),
            "ods.i2.tracks": next((m for m in com_trilha), trilhas[0] if trilhas else None),
            "ods.s1.position": next((m for m in com_posicao), posicoes[0] if posicoes else None),
        }

    contagem_real: Counter = Counter()

    def deste_teste(topico: str, m: dict) -> bool:
        if topico == "ods.s3.alert":
            return payload(m).get("event_id") == event_id or payload(m).get("alert_id") == alert_id
        if topico == "ods.s4.clip":
            return payload(m).get("event_id") == event_id
        if topico == "ods.i9.ppe_compliance" and m.get("session_id") == sessao_i1:
            return True
        if sessao_video and m.get("session_id") == sessao_video and contagem_real[topico] < AMOSTRA_CONTRATO:
            contagem_real[topico] += 1
            return True
        return False

    t.validar_contratos("C11", bus, incluir=deste_teste)
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
