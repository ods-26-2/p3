#!/usr/bin/env python3
"""Teste de aceitação do A2 · Acesso / identificação (P3 / SIS-1).

Cadeia: I6 -> ods.i6.code_read -> A2 (decide e passa a catraca simulada)
        A2 -> ods.s4.capture.command -> S4 -> ods.s4.capture.reply + ods.s4.clip -> A2

Roteiro:
  1. Assina os tópicos e escreve PRONTO.
  2. Observa leituras reais do I6 (vídeo/câmera configurados) por I6_OBSERVAR_S segundos.
  3. Injeta duas leituras de QR como o I6 publicaria (entrada simulada: I6), com o
     conteúdo cifrado do mesmo jeito que o gerador de crachás do VER-2: um crachá válido
     agora e um vencido. Espera o registro de acesso do válido na API do A2 (com a mídia
     do S4) e nenhum registro do vencido.
O CPF de teste começa com 999 (fictício); o registro fica no banco do A2 como evidência do teste.
"""

import os
import struct
import sys
import time
import uuid

sys.path.insert(0, "/comum")
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes  # noqa: E402

from ods_aceite import (AVISO, BLOQUEADO, FALHOU, PASSOU, Barramento, Teste, pausa,  # noqa: E402
                        envelope, http, iso, payload, pronto)

API = os.environ.get("A2_API", "http://a2:8001")
FONTE = os.environ.get("I6_SOURCE_ID", "cam-portaria")
CHAVE = os.environ["A2_AES_KEY"].encode("ascii")
OBSERVAR_S = int(os.environ.get("I6_OBSERVAR_S", "30"))
CPF_VALIDO, CPF_VENCIDO = 999000111, 999000222


def cracha(cpf_base: int, inicio: int, fim: int) -> str:
    """16 bytes: cpf_base, início, fim, máscara de dias (todos), 3 bytes livres -> AES-256-ECB -> hex."""
    claro = struct.pack(">III", cpf_base, inicio, fim) + bytes([0x7F, 0, 0, 0])
    cifra = Cipher(algorithms.AES(CHAVE), modes.ECB()).encryptor()
    return (cifra.update(claro) + cifra.finalize()).hex()


def leitura(sessao: str, seq: int, dado: str) -> dict:
    return envelope("ods.i6.code_read", "event", "I6",
                    {"frame_index": seq, "code_type": "QR_CODE", "decoded_data": dado,
                     "bbox": [812, 300, 1010, 498]},
                    captured_at=iso(), source_id=FONTE, session_id=sessao, sequence=seq,
                    artifact_version="aceite-a2-p3")


def acessos(cpf_completo_prefixo: str) -> list[dict] | None:
    """Registros do CPF de teste; None se a API não respondeu."""
    codigo, corpo = http("GET", f"{API}/acessos?limit=200")
    if codigo != 200:
        return None
    lista = corpo if isinstance(corpo, list) else (corpo.get("items") or corpo.get("acessos") or [])
    return [a for a in lista if str(a.get("cpf", "")).startswith(cpf_completo_prefixo)]


def main() -> int:
    t = Teste("a2", "I6 -> A2 -> catraca simulada -> S4, pelo Kafka da turma e pela API do A2")
    bus = Barramento("A2-ACEITE")
    pronto(bus, ["ods.i6.code_read", "ods.s4.capture.command", "ods.s4.capture.reply", "ods.s4.clip"],
           "observador do A2")

    codigo, saude = http("GET", f"{API}/health")
    t.registrar("C01", "API de registros do A2 (/health)", PASSOU if codigo == 200 else FALHOU, f"HTTP {codigo}")

    # Leituras reais do I6 ---------------------------------------------------------
    reais = bus.esperar(lambda: [m for m in bus.mensagens("ods.i6.code_read") if m.get("producer") == "I6"
                                 and m.get("artifact_version") != "aceite-a2-p3"], OBSERVAR_S) or []
    t.registrar("C02", f"Leituras reais do I6 em {OBSERVAR_S} s", PASSOU if reais else AVISO,
                f"{len(reais)} leitura(s)" if reais else
                "nenhum QR na fonte do I6 (vídeo sem crachá ou câmera apontada para outro lado)")

    # Crachás injetados ------------------------------------------------------------
    sessao, agora_s = str(uuid.uuid4()), int(time.time())
    mid_ok = bus.publicar(leitura(sessao, 0, cracha(CPF_VALIDO, agora_s - 600, agora_s + 3600)))
    pausa(4)  # a catraca simulada libera e registra a passagem (~2 s)
    mid_venc = bus.publicar(leitura(sessao, 1, cracha(CPF_VENCIDO, agora_s - 7200, agora_s - 3600)))

    reg_ok = bus.esperar(lambda: [a for a in (acessos(str(CPF_VALIDO)) or [])
                                  if a.get("i6_message_id") in (None, mid_ok)], 40) or []
    t.registrar("C03", "Crachá válido: passagem registrada pelo A2 (entrada simulada: I6)",
                PASSOU if reg_ok else FALHOU,
                f"registro {reg_ok[0].get('id')} direção {reg_ok[0].get('direction')}" if reg_ok
                else "nenhum registro em /acessos para o CPF de teste")
    reg_venc = acessos(str(CPF_VENCIDO))
    if reg_venc is None:
        t.registrar("C04", "Crachá vencido: acesso negado (sem registro de passagem)", FALHOU,
                    "a API de registros do A2 não respondeu")
    else:
        t.registrar("C04", "Crachá vencido: acesso negado (sem registro de passagem)",
                    PASSOU if not reg_venc else FALHOU, f"{len(reg_venc)} registro(s)")

    pedidos = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.capture.command")
                                   if m.get("producer") == "A2"], 30) or []
    t.registrar("C05", "Snapshot pedido pelo A2 ao S4 (ods.s4.capture.command)",
                PASSOU if pedidos else FALHOU, f"{len(pedidos)} pedido(s)")
    mids = {m.get("message_id") for m in pedidos}
    resp = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.capture.reply")
                                if m.get("correlation_id") in mids], 30) or []
    clipes = bus.esperar(lambda: [m for m in bus.mensagens("ods.s4.clip")
                                  if m.get("correlation_id") in mids], 30) or []
    if not pedidos:
        t.registrar("C06", "Snapshot do S4 entregue (reply + ods.s4.clip)", BLOQUEADO, "sem pedido")
    else:
        t.registrar("C06", "Snapshot do S4 entregue (reply + ods.s4.clip)", PASSOU if clipes else FALHOU,
                    f"{len(resp)} reply(s), {len(clipes)} descritor(es)"
                    + (f"; erro {payload(resp[0]).get('error')}" if resp and payload(resp[0]).get('status') == 'ERROR' else ""))
    if reg_ok:
        estado = bus.esperar(lambda: [a.get("media_status") for a in (acessos(str(CPF_VALIDO)) or [])
                                      if a.get("media_status") not in (None, "NONE", "PENDING", "REQUESTED")], 30)
        t.registrar("C07", "Mídia vinculada ao registro de acesso", PASSOU if estado else AVISO,
                    f"media_status {estado[0] if estado else reg_ok[0].get('media_status')}")

    t.registrar("C08", "I6 lendo os quadros do P4", BLOQUEADO,
                "o I6 espera um socket TCP que o P4 não oferece; a build usa o modo câmera/arquivo do I6")

    def deste_teste(topico: str, m: dict) -> bool:
        if topico == "ods.i6.code_read":
            return m.get("producer") == "I6" and m.get("artifact_version") != "aceite-a2-p3"
        if topico == "ods.s4.capture.command":
            return m.get("message_id") in mids
        return m.get("correlation_id") in mids

    t.validar_contratos("C09", bus, incluir=deste_teste, produtores={"ods.s4.capture.command": "A2"})
    t.extras["mensagens_injetadas"] = {"cracha_valido": mid_ok, "cracha_vencido": mid_venc}
    return t.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
