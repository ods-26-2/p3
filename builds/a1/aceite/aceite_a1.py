#!/usr/bin/env python3
"""Teste de aceitação do A1 · Indústria / inspeção (P3 / SIS-1).

Observa a cadeia real pelo Kafka da turma e pela API do A1:
  I8 (publisher real, 4 eventos de exemplo) -> ods.industria.defeito_classificado -> A1
  A1 -> ods.s4.capture.command -> S4 -> ods.s4.capture.reply + ods.s4.clip -> A1 (evidência)

Roteiro (o a1.sh faz os passos de fora):
  1. Assina os tópicos e escreve PRONTO.
  2. Espera o passo "i8" (o a1.sh roda o publisher do I8).
  3. Confere a ingestão no A1 pela API, os pedidos de evidência e as respostas do S4.
"""

import os
import sys

sys.path.insert(0, "/comum")
from ods_aceite import (AVISO, BLOQUEADO, CONTRATOS, EV_SINAL, FALHOU, PASSOU, Barramento,  # noqa: E402
                        Teste, esperar_passo, http, payload, pronto)

API = os.environ.get("A1_API", "http://a1-backend:8000/api/v1")
TOPICO_I8 = "ods.industria.defeito_classificado"
# Contrato 2.0 do VER-1 (docs/contratos/kafka-i8-2.0.md do I8): envelope 1.0 + occurred_at.
CONTRATOS[TOPICO_I8] = ("event", "I8", ("frame_index", "detection_id", "bbox", "result",
                                         "taxonomy_version", "confidence", "similarity"), EV_SINAL)


def main() -> int:
    t = Teste("a1", "I8 (eventos de exemplo) -> A1 -> S4, pelo Kafka da turma e pela API do A1")
    bus = Barramento("A1-ACEITE")
    pronto(bus, [TOPICO_I8, "ods.i8.piece_analysis", "ods.s4.capture.command",
                 "ods.s4.capture.reply", "ods.s4.clip"], "observador do A1")

    if not esperar_passo(bus, "i8", 600):
        t.registrar("C01", "Eventos do I8 publicados", FALHOU, "o passo i8 não terminou em 10 min")
        return t.concluir(bus)
    eventos = bus.esperar(lambda: [m for m in bus.mensagens(TOPICO_I8)
                                   if m.get("artifact_version") == "p3-exemplos-i8"], 30) or []
    ids = {m["message_id"] for m in eventos if m.get("message_id")}
    resultados = sorted({payload(m).get("result") for m in eventos} - {None})
    t.registrar("C01", "Eventos do I8 no Kafka (publisher real, contrato 2.0)",
                PASSOU if len(ids) >= 4 else FALHOU, f"{len(ids)} evento(s): {', '.join(resultados)}")

    # Ingestão pelo A1 (API) ---------------------------------------------------------
    def no_a1():
        codigo, corpo = http("GET", f"{API}/inspections?limit=100")
        if codigo != 200 or not isinstance(corpo, dict):
            return None
        return [i for i in corpo.get("items", []) if (i.get("origin") or {}).get("message_id") in ids]

    inspecoes = bus.esperar(no_a1, 60) or []
    codigo, saude = http("GET", f"{API}/health")
    if not ids:
        t.registrar("C02", "Inspeções registradas pelo A1", BLOQUEADO, "sem eventos do I8 para conferir")
    elif len(inspecoes) == len(ids):
        t.registrar("C02", "Inspeções registradas pelo A1", PASSOU, f"{len(inspecoes)}/{len(ids)} pela API")
    else:
        t.registrar("C02", "Inspeções registradas pelo A1", FALHOU,
                    f"{len(inspecoes)}/{len(ids)} na API; health: "
                    f"{saude.get('status') if isinstance(saude, dict) else codigo}")

    # Evidência: A1 -> S4 -> A1 -----------------------------------------------------
    pedidos = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.capture.command")
                                   if m.get("producer") == "A1"], 60) or []
    t.registrar("C03", "Pedidos de evidência do A1 ao S4 (ods.s4.capture.command)",
                PASSOU if pedidos else FALHOU, f"{len(pedidos)} pedido(s)")
    mids = {m.get("message_id") for m in pedidos}
    respostas = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.capture.reply")
                                     if m.get("correlation_id") in mids], 45) or []
    oks = [m for m in respostas if payload(m).get("status") == "OK"]
    if not pedidos:
        t.registrar("C04", "Respostas do S4 aos pedidos do A1", BLOQUEADO, "sem pedidos")
    elif oks:
        t.registrar("C04", "Respostas do S4 aos pedidos do A1", PASSOU, f"{len(oks)} OK de {len(respostas)}")
    else:
        erro = payload(respostas[0]).get("error") if respostas else "sem resposta"
        t.registrar("C04", "Respostas do S4 aos pedidos do A1", FALHOU, str(erro))
    clipes = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.clip")
                                  if m.get("correlation_id") in mids], 45) or []
    t.registrar("C05", "Clipes do S4 para o A1 (ods.s4.clip)", PASSOU if clipes else (FALHOU if oks else BLOQUEADO),
                f"{len(clipes)} clipe(s)")

    if inspecoes and clipes:
        estados = bus.esperar(lambda: [((i.get("evidence") or {}).get("state")) for i in (no_a1() or [])
                                       if (i.get("evidence") or {}).get("state") == "AVAILABLE"], 45) or []
        t.registrar("C06", "Evidência disponível na inspeção do A1", PASSOU if estados else FALHOU,
                    f"{len(estados)} inspeção(ões) com evidência AVAILABLE")

    # Lacunas conhecidas -----------------------------------------------------------
    t.registrar("C07", "Tópico da 6c (ods.i8.piece_analysis)", AVISO,
                "o A1 e o I8 usam ods.industria.defeito_classificado (contrato 2.0 do VER-1)")
    t.registrar("C08", "Triagem física pelo P7", BLOQUEADO, "o P7 ainda não atende pelo Kafka")
    t.registrar("C09", "Inferência real do I8 sobre imagens", BLOQUEADO,
                "o repositório do I8 não traz modelo treinado; os eventos são os exemplos do próprio I8")

    def deste_teste(topico: str, m: dict) -> bool:
        if topico == TOPICO_I8:
            return m.get("message_id") in ids
        if topico == "ods.s4.capture.command":
            return m.get("message_id") in mids
        return m.get("correlation_id") in mids

    t.validar_contratos("C10", bus, incluir=deste_teste, produtores={"ods.s4.capture.command": "A1"})
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
