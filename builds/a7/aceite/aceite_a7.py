#!/usr/bin/env python3
"""Teste de aceitação do A7 · Restaurante / áudio e voz (P3 / SIS-1).

Cadeia: (P5) -> I5 -> ods.i5.transcript -> A7 (intenção, carrinho, jornada).

Roteiro (o a7.sh faz o passo de fora):
  1. Assina os tópicos e escreve PRONTO.
  2. Injeta uma transcrição no formato que o I5 publica hoje (entrada simulada: I5), com uma
     origem só do teste, e confere a sessão e o carrinho do A7 pela API. Apaga a sessão no fim.
  3. Passo "fala": o I5 real transcreveu I5_AUDIO (Whisper em CPU) e publicou.
     Confere a transcrição no Kafka e a sessão do A7 para a origem I5_ORIGEM.
"""

import os
import sys
import uuid

sys.path.insert(0, "/comum")
from ods_aceite import (BLOQUEADO, FALHOU, PASSOU, AVISO, Barramento, Teste,  # noqa: E402
                        esperar_passo, http, iso, payload, pronto)

API = os.environ.get("A7_API", "http://a7:8000")
ORIGEM_REAL = os.environ.get("I5_ORIGEM", "mic_balcao_1")
ORIGEM_TESTE = f"aceite-p3-{uuid.uuid4().hex[:6]}"
FRASE = "quero um suco natural de laranja"


def transcricao_simulada() -> dict:
    """Mesmo formato de construir_envelope_transcricao() do I5 (src/kafka_publisher.py), mais o
    contexto EV-SINAL da 6c."""
    agora = iso()
    return {
        "message_id": str(uuid.uuid4()), "message_type": "event", "schema": "ods.i5.transcript",
        "schema_version": "1.0", "producer": "I5", "artifact_version": "aceite-a7-p3",
        "occurred_at": agora, "published_at": agora, "captured_at": agora, "source_id": "mic-aceite",
        "session_id": str(uuid.uuid4()), "sequence": 0,
        "payload": {"origem": ORIGEM_TESTE, "timestamp_inicio": agora, "timestamp_fim": agora,
                    "texto_transcrito": FRASE, "texto_preprocessado": FRASE, "confianca_geral": 0.95,
                    "confidence": 0.95, "uncertain": False, "duvida_explicita": False},
    }


def main() -> int:
    t = Teste("a7", "I5 (simulado e real) -> A7, pelo Kafka da turma e pela API do A7")
    bus = Barramento("A7-ACEITE")
    pronto(bus, ["ods.i5.transcript"], "observador do A7")

    codigo, _ = http("GET", f"{API}/health")
    t.registrar("C01", "A7 no ar (/health)", PASSOU if codigo == 200 else FALHOU, f"HTTP {codigo}")

    # Transcrição injetada -----------------------------------------------------------------
    simulada = transcricao_simulada()
    bus.publicar(simulada)
    sessao = bus.esperar(lambda: (lambda c, s: s if c == 200 else None)(*http("GET", f"{API}/sessoes/{ORIGEM_TESTE}")), 30)
    t.registrar("C02", "A7 abre a sessão da fala (entrada simulada: I5)", PASSOU if sessao else FALHOU,
                f"origem {ORIGEM_TESTE}" if sessao else "sessão não criada: o A7 recebeu a transcrição?")
    if sessao:
        codigo, carrinho = http("GET", f"{API}/carrinho/{ORIGEM_TESTE}")
        itens = carrinho.get("itens", []) if isinstance(carrinho, dict) else []
        t.registrar("C03", f"Intenção vira item no carrinho (\"{FRASE}\")", PASSOU if itens else AVISO,
                    ", ".join(f"{i.get('quantidade')}x {i.get('nome')}" for i in itens) if itens else
                    "sem item: o classificador (Ollama ausente -> RapidFuzz) não reconheceu o pedido")
        http("DELETE", f"{API}/sessoes/{ORIGEM_TESTE}")

    # I5 real --------------------------------------------------------------------------------
    reais = []
    if esperar_passo(bus, "fala", 1800):
        reais = bus.esperar(lambda: [m for m in bus.mensagens("ods.i5.transcript")
                                     if m.get("producer") == "I5" and m.get("artifact_version") != "aceite-a7-p3"], 20) or []
    if reais:
        p = payload(reais[-1])
        texto = p.get("texto_transcrito") or p.get("transcribed_text")
        t.registrar("C04", "I5 transcreve o áudio e publica (ods.i5.transcript)", PASSOU,
                    f"\"{texto}\" (confiança {p.get('confianca_geral', p.get('confidence'))}, origem {p.get('origem')})")
        origem = p.get("origem") or ORIGEM_REAL
        sessao_real = bus.esperar(lambda: http("GET", f"{API}/sessoes/{origem}")[0] == 200, 30)
        t.registrar("C05", "A7 abre a sessão da fala real", PASSOU if sessao_real else FALHOU, f"origem {origem}")
    else:
        t.registrar("C04", "I5 transcreve o áudio e publica (ods.i5.transcript)", FALHOU,
                    "nenhuma transcrição do I5 real (o passo fala rodou? veja a saída do ./a7.sh testar)")

    t.registrar("C06", "Áudio ao vivo do P5", BLOQUEADO, "o P5 ainda não publica no Kafka (só script de teste)")
    t.registrar("C07", "Métricas do S5 para o A7", BLOQUEADO,
                "o A7 escuta ods.s5.event.metrics (6c: ods.s5.event_metrics) e o S5 não tem fonte de eventos do A7")

    t.validar_contratos("C08", bus, incluir=lambda top, m: m.get("producer") == "I5"
                        and m.get("artifact_version") != "aceite-a7-p3")
    if t.por_schema.get("ods.i5.transcript", {}).get("invalidas"):
        t.registrar("C09", "Payload do I5 na 6c", AVISO,
                    "o I5 publica texto_transcrito/confianca_geral/origem; a 6c pede transcribed_text, "
                    "normalized_text, start_at, end_at (o A7 aceita o formato do I5)")
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
