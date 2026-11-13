#!/usr/bin/env python3
"""Teste de aceitação do A6 · Libras / acessibilidade (P3 / SIS-1).

Cadeia: I4 -> ods.i4.sign -> A6 (agrega a frase)
        A6 -> ods.s6.synthesis.command -> S6 (real, do repo i4) -> ods.s6.synthesis.reply -> A6

Roteiro (o a6.sh faz o passo de fora):
  1. Assina os tópicos e escreve PRONTO.
  2. Passo "amostra": o publicador do próprio I4 mandou um sinal do léxico.
     Confere o sinal no Kafka e no estado do A6 (/api/state).
  3. Pede uma tradução pela API do A6 (/api/translate) e confere o comando ao S6, a reply
     do S6 real e o arquivo da trajetória na pasta compartilhada.
"""

import os
import sys

sys.path.insert(0, "/comum")
from ods_aceite import (AVISO, BLOQUEADO, FALHOU, PASSOU, Barramento, Teste,  # noqa: E402
                        esperar_passo, http, payload, pronto)

API = os.environ.get("A6_API", "http://a6:8080")
SINAL = os.environ.get("I4_AMOSTRA_SINAL", "Aluno").upper()
TRAJETORIAS = os.environ.get("TRAJETORIAS_DIR", "/trajetorias")
FRASE_TESTE = os.environ.get("A6_FRASE_TESTE", "aluno conhecer banheiro")


def main() -> int:
    t = Teste("a6", "I4 (amostra) -> A6 -> S6 real -> A6")
    bus = Barramento("A6-ACEITE")
    pronto(bus, ["ods.i4.sign", "ods.i4.facial_marker", "ods.s6.synthesis.command", "ods.s6.synthesis.reply"],
           "observador do A6")

    codigo, estado = http("GET", f"{API}/api/state")
    ok = codigo == 200 and isinstance(estado, dict) and estado.get("kafka_connected")
    t.registrar("C01", "A6 no ar e ligado ao Kafka (/api/state)", PASSOU if ok else FALHOU,
                f"HTTP {codigo}, léxico {estado.get('lexicon_version') if isinstance(estado, dict) else '?'}")

    # Sinal do I4 -------------------------------------------------------------------------
    sinais = []
    if esperar_passo(bus, "amostra", 300):
        sinais = bus.esperar(lambda: [m for m in bus.mensagens("ods.i4.sign") if m.get("producer") == "I4"], 15) or []
    t.registrar("C02", "Sinal publicado pelo I4 (publica_amostra do INV-2)", PASSOU if sinais else FALHOU,
                f"{payload(sinais[-1]).get('sign')} ({payload(sinais[-1]).get('confidence')})" if sinais else "")
    if sinais:
        def no_a6():
            _, e = http("GET", f"{API}/api/state")
            if not isinstance(e, dict):
                return False
            texto = str(e.get("recent_i4_events", "")) + str(e.get("active_contexts", "")) + str(e.get("closed_sentences", ""))
            return SINAL in texto.upper()
        t.registrar("C03", "A6 recebeu o sinal (estado do tradutor)", PASSOU if bus.esperar(no_a6, 20) else FALHOU)

    # Tradução -> S6 ----------------------------------------------------------------------
    # Frase só com glosas que o S6 real conhece: ele tem trajetória para 20 sinais (os do
    # MINDS-Libras em i4/lexicon), enquanto o léxico do A6 lista 100. Com nenhuma conhecida,
    # o S6 responde EMPTY_SEQUENCE.
    codigo, res = http("POST", f"{API}/api/translate", {"text": FRASE_TESTE, "speed_factor": 1.0}, timeout=30)
    cmds = bus.esperar(lambda: [m for m in bus.mensagens("ods.s6.synthesis.command") if m.get("producer") == "A6"], 15) or []
    t.registrar("C04", "A6 pede a síntese ao S6 (ods.s6.synthesis.command)", PASSOU if cmds else FALHOU,
                f"HTTP {codigo}; glosas {payload(cmds[-1]).get('glosses')}" if cmds else f"HTTP {codigo}")
    mid = cmds[-1].get("message_id") if cmds else None
    resp = bus.esperar(lambda: bus.correlacionadas(["ods.s6.synthesis.reply"], mid), 30) if mid else []
    resp = [m for _, m in resp or []]
    reais = [m for m in resp if m.get("producer") == "S6"]
    if not mid:
        t.registrar("C05", "S6 responde com a trajetória", BLOQUEADO, "sem comando")
    elif reais and payload(reais[0]).get("status") == "OK":
        p = payload(reais[0])
        t.registrar("C05", "S6 responde com a trajetória", PASSOU,
                    f"{p.get('trajectory_ref')}, {p.get('frame_count')} quadros, desconhecidas {p.get('unknown_signs')}")
        nome = str(p.get("trajectory_ref", "")).rsplit("/", 1)[-1]
        existe = bool(nome) and os.path.exists(os.path.join(TRAJETORIAS, nome))
        t.registrar("C06", "Trajetória na pasta compartilhada S6 -> A6", PASSOU if existe else FALHOU, nome)
    else:
        t.registrar("C05", "S6 responde com a trajetória", FALHOU,
                    f"{len(resp)} reply(s); {payload(resp[0]).get('error') if resp else 'sem resposta do S6'}")

    # Cobertura: o léxico inteiro do A6 pedido direto ao S6 real (o teste faz o papel do A6).
    _, estado = http("GET", f"{API}/api/state")
    glosas = [s.get("gloss") for s in (estado.get("lexicon_signs") or [])] if isinstance(estado, dict) else []
    if glosas:
        _, cob = bus.pedir("ods.s6.synthesis.command", "S6",
                           {"glosses": glosas, "speed_factor": 1.0, "lexicon_version": estado.get("lexicon_version")},
                           ["ods.s6.synthesis.reply"], espera_s=60)
        pc = payload(cob[0][1]) if cob else {}
        desconhecidas = pc.get("unknown_signs")
        if desconhecidas is None:
            t.registrar("C07", "Glosas do léxico do A6 que o S6 sabe sintetizar", FALHOU,
                        f"sem resposta útil do S6: {pc.get('error') if pc else 'nenhuma'}")
        else:
            n = len(glosas) - len(desconhecidas)
            t.registrar("C07", "Glosas do léxico do A6 que o S6 sabe sintetizar", PASSOU if not desconhecidas else AVISO,
                        f"{n} de {len(glosas)}" + (f"; sem trajetória no S6: {', '.join(desconhecidas[:12])}"
                                                    + ("…" if len(desconhecidas) > 12 else "") if desconhecidas else ""))
    else:
        t.registrar("C07", "Glosas do léxico do A6 que o S6 sabe sintetizar", FALHOU, "o A6 não informou o léxico")

    t.registrar("C08", "Tela do tradutor mostra a síntese do S6 real", AVISO,
                "a página usa o motor interno do A6 (trajetória-modelo repetida); a resposta do S6 real só vai para o log")
    t.registrar("C09", "I4 ao vivo (câmera) e captura de léxico", BLOQUEADO,
                "o I4 ao vivo depende do servidor C++ do INV-2 e não está na build")

    def deste_teste(topico: str, m: dict) -> bool:
        if topico == "ods.i4.sign":
            return m.get("producer") == "I4"
        if topico == "ods.s6.synthesis.command":
            return m.get("message_id") == mid
        if topico == "ods.s6.synthesis.reply":
            return m.get("correlation_id") == mid
        return False

    t.validar_contratos("C10", bus, incluir=deste_teste)
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
