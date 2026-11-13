#!/usr/bin/env python3
"""Teste de aceitação do A8 — "A8 simulado" (P3 / SIS-1).

Faz, pelo Kafka da turma, o papel que a Especificação de interfaces 1.0 (6c) dá ao A8:
escuta o que o A8 consome, envia os pedidos que o A8 envia e confere as respostas e o
envelope de cada mensagem com o validador do B4 (tests/integration/contract_validation.py).

Roteiro (o a8.sh orquestra os passos de fora: I7, vídeo do P4 e reinício do S4):
  1. Assina os tópicos a partir do fim e escreve PRONTO no log.
  2. Recebe as leituras de placa do I7 e a sessão do vídeo do P4.
  3. Acompanha a cadeia da sessão (I1 -> I2 -> S1 -> S5) até ela ficar quieta.
  4. Pede, como o A8: métricas e mapa de calor ao S5, clipe e descritor ao S4, regras ao S2.
  5. Valida o envelope de tudo o que recebeu e grava o relatório em RESULT_DIR.

Zonas em PIXELS (zones-a8-p3-1): sem calibração, o I3 não participa.
Saída: 0 se nenhum item FALHOU (BLOQUEADO e AVISO não reprovam), 1 caso contrário.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.request
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from confluent_kafka import OFFSET_END, Consumer, KafkaError, Producer

BROKER = os.environ["KAFKA_BROKER"]
S4_HTTP = os.environ.get("S4_HTTP", "http://s4:18084")
SOURCE_ID = os.environ.get("VIDEO_SOURCE_ID", "file_cam0")
ZONAS = [z for z in os.environ.get("ZONAS", "vaga-1,vaga-2").split(",") if z]
RESULT_DIR = os.environ.get("RESULT_DIR", "/resultados")
B4_DIR = os.environ.get("B4_DIR", "/b4")
ESPERA_SESSAO_S = int(os.environ.get("ESPERA_SESSAO_S", "300"))
QUIETO_S = int(os.environ.get("QUIETO_S", "25"))
ESPERA_METRICAS_S = int(os.environ.get("ESPERA_METRICAS_S", "75"))
ESPERA_RESPOSTA_S = int(os.environ.get("ESPERA_RESPOSTA_S", "20"))
ESPERA_BUFFER_S4_S = int(os.environ.get("ESPERA_BUFFER_S4_S", "120"))

# O que a especificação 6c diz que o A8 consome, mais a sessão e os elos da cadeia.
TOPICOS_EVENTOS = [
    "ods.session.started",
    "ods.i1.detections",
    "ods.i2.tracks",
    "ods.i3.calibration",
    "ods.i7.plate_read",
    "ods.s1.position",
    "ods.s1.zone_transition",
    "ods.s1.zone_occupancy",
    "ods.s2.entity",
    "ods.s2.event",
    "ods.s4.clip",
    "ods.s5.zone_metrics",
    "ods.s5.event_metrics",
]
# Respostas aos pedidos do A8. ods.s4.clip.query.reply é o nome que o S4 usa hoje;
# a especificação define ods.s4.clip.reply.
TOPICOS_RESPOSTAS = [
    "ods.s5.metrics.reply",
    "ods.s5.heatmap.reply",
    "ods.s4.capture.reply",
    "ods.s4.clip.reply",
    "ods.s4.clip.query.reply",
    "ods.s2.rules.reply",
]
CADEIA = ("ods.i1.detections", "ods.i2.tracks", "ods.s1.position",
          "ods.s1.zone_transition", "ods.s1.zone_occupancy")

EV_SINAL = ("captured_at", "source_id", "session_id", "sequence", "artifact_version")
EV_SINAL_SEM_ARTEFATO = ("captured_at", "source_id", "session_id", "sequence")
EV_SERVICO = ("captured_at", "session_id", "sequence")
RPL = ("correlation_id",)

# schema -> (message_type, producer, campos do payload, campos de contexto do envelope)
# Campos do payload: os mesmos que as suítes do B4 exigem; os demais, da especificação 1.0.
CONTRATOS = {
    "ods.session.started": ("event", "P4", ("mode", "started_at", "sources"), EV_SINAL_SEM_ARTEFATO),
    "ods.i1.detections": ("event", "I1", ("frame_index", "image_width", "image_height", "detections"), EV_SINAL),
    "ods.i2.tracks": ("event", "I2", ("frame_index", "tracks"), EV_SINAL),
    "ods.i7.plate_read": ("event", "I7", ("frame_index", "class", "plate_layout", "license_plate",
                                          "confidence", "character_confidences"), EV_SINAL),
    "ods.s1.position": ("event", "S1", ("frame_index", "positions"), EV_SINAL),
    "ods.s1.zone_transition": ("event", "S1", ("track_id", "class", "zone_id", "transition", "entered_at"), EV_SINAL),
    "ods.s1.zone_occupancy": ("event", "S1", ("zone_id", "count", "count_by_class", "track_ids"), EV_SINAL),
    "ods.s5.zone_metrics": ("event", "S5", ("zone_id", "window_start_at", "window_end_at", "granularity",
                                            "total_count", "occupancy_peak", "occupancy_avg", "dwell_avg_s"), EV_SERVICO),
    "ods.s4.clip": ("event", "S4", ("clip_id", "media_type", "media_uri", "start_at", "end_at",
                                    "hash_sha256", "expires_at"), EV_SERVICO),
    "ods.s5.metrics.reply": ("reply", "S5", ("status",), RPL),
    "ods.s5.heatmap.reply": ("reply", "S5", ("status",), RPL),
    "ods.s4.capture.reply": ("reply", "S4", ("status",), RPL),
    "ods.s4.clip.reply": ("reply", "S4", ("status",), RPL),
    "ods.s4.clip.query.reply": ("reply", "S4", ("status",), RPL),
    "ods.s2.rules.reply": ("reply", "S2", ("status",), RPL),
}

PASSOU, FALHOU, BLOQUEADO, AVISO = "PASSOU", "FALHOU", "BLOQUEADO", "AVISO"


# ----------------------------------------------------------------------------- utilidades

def agora() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def ler_iso(valor: object) -> datetime | None:
    if not isinstance(valor, str):
        return None
    try:
        return datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except ValueError:
        return None


def log(texto: str) -> None:
    print(f"[aceite {datetime.now().strftime('%H:%M:%S')}] {texto}", flush=True)


class Barramento:
    """Consumidor que começa no fim de cada tópico e guarda tudo o que recebe."""

    def __init__(self) -> None:
        self.recebidas: dict[str, list[tuple[float, dict]]] = defaultdict(list)
        self.invalidas: list[tuple[str, str]] = []
        self._atribuidos: set[str] = set()
        self.consumer = Consumer({
            "bootstrap.servers": BROKER,
            "group.id": f"aceite-a8-{uuid.uuid4()}",
            "enable.auto.commit": False,
            "auto.offset.reset": "latest",
        })
        self.producer = Producer({"bootstrap.servers": BROKER, "acks": "all"})

    def assinar(self, topicos: list[str], espera_s: int = 60) -> list[str]:
        def ao_atribuir(consumer, particoes):
            for p in particoes:
                p.offset = OFFSET_END
                self._atribuidos.add(p.topic)
            consumer.assign(particoes)

        self.consumer.subscribe(topicos, on_assign=ao_atribuir)
        limite = time.monotonic() + espera_s
        while time.monotonic() < limite and not set(topicos) <= self._atribuidos:
            self.receber(0.5)
        # Mais alguns polls para as posições de fim serem resolvidas antes do PRONTO.
        for _ in range(6):
            self.receber(0.5)
        return sorted(set(topicos) - self._atribuidos)

    def receber(self, timeout: float = 0.5) -> int:
        n = 0
        msg = self.consumer.poll(timeout)
        while msg is not None:
            if msg.error():
                if msg.error().code() not in (KafkaError._PARTITION_EOF, KafkaError.UNKNOWN_TOPIC_OR_PART):
                    log(f"erro do consumidor: {msg.error()}")
            else:
                try:
                    corpo = json.loads(msg.value())
                    if not isinstance(corpo, dict):
                        raise ValueError("não é objeto JSON")
                    self.recebidas[msg.topic()].append((time.monotonic(), corpo))
                except (ValueError, TypeError) as erro:
                    self.invalidas.append((msg.topic(), str(erro)))
                n += 1
            msg = self.consumer.poll(0)
        return n

    def publicar(self, schema: str, envelope: dict) -> None:
        self.producer.produce(schema, json.dumps(envelope).encode("utf-8"))
        self.producer.flush(10)

    def pedir(self, schema: str, alvo: str, payload: dict, topicos_resposta: list[str],
              espera_s: int = ESPERA_RESPOSTA_S, todas: bool = False) -> tuple[str, list[tuple[str, dict]]]:
        """Envia query/command com perfil CMD e devolve as respostas correlacionadas."""
        mid = str(uuid.uuid4())
        envelope = {
            "message_type": "command" if schema.endswith(".command") else "query",
            "message_id": mid,
            "schema": schema,
            "schema_version": "1.0",
            "producer": "A8",
            "target": alvo,
            "published_at": iso(agora()),
            "payload": payload,
        }
        self.publicar(schema, envelope)
        limite = time.monotonic() + espera_s
        respostas: list[tuple[str, dict]] = []
        while time.monotonic() < limite:
            self.receber(0.5)
            respostas = [(t, m) for t in topicos_resposta for _, m in self.recebidas.get(t, [])
                         if m.get("correlation_id") == mid]
            if respostas and not todas:
                break
        return mid, respostas

    def da_sessao(self, topico: str, sessao: str) -> list[dict]:
        return [m for _, m in self.recebidas.get(topico, []) if m.get("session_id") == sessao]


def eh_da_fonte(msg: dict) -> bool:
    p = msg.get("payload") if isinstance(msg.get("payload"), dict) else {}
    return (msg.get("source_id") == SOURCE_ID or p.get("source_id") == SOURCE_ID
            or SOURCE_ID in (p.get("sources") or []))


def buffer_s4() -> dict | None:
    try:
        with urllib.request.urlopen(f"{S4_HTTP}/api/v1/buffer/stats", timeout=3) as resposta:
            return json.loads(resposta.read())
    except Exception:  # noqa: BLE001 - qualquer falha significa "ainda não"
        return None


# ----------------------------------------------------------------------------- teste

def main() -> int:
    itens: list[dict] = []

    def registrar(cod: str, descricao: str, estado: str, detalhe: str = "") -> None:
        itens.append({"item": cod, "verificacao": descricao, "resultado": estado, "detalhe": detalhe})
        log(f"{cod} {estado:9} {descricao}" + (f" — {detalhe}" if detalhe else ""))

    try:
        sys.path.insert(0, B4_DIR)
        from contract_validation import validate_message  # type: ignore
    except ImportError:
        validate_message = None

    bus = Barramento()
    faltando = bus.assinar(TOPICOS_EVENTOS + TOPICOS_RESPOSTAS)
    if faltando:
        log(f"tópicos sem partição atribuída (não existem no broker?): {', '.join(faltando)}")
    inicio = agora()
    log(f"PRONTO — escutando {BROKER} como A8 (fonte {SOURCE_ID}, zonas {', '.join(ZONAS)})")

    # 2-3. Sessão do P4 e cadeia até ficar quieta ------------------------------------
    sessao: str | None = None
    sessao_em: float | None = None
    sessao_inicio: datetime | None = None
    limite = time.monotonic() + ESPERA_SESSAO_S
    while time.monotonic() < limite:
        bus.receber(0.5)
        if sessao is None:
            for t, m in bus.recebidas.get("ods.session.started", []):
                if eh_da_fonte(m) and m.get("session_id"):
                    sessao, sessao_em = m["session_id"], t
                    sessao_inicio = ler_iso(m.get("captured_at") or m.get("published_at")
                                            or m.get("occurred_at")) or agora()
                    log(f"sessão do vídeo recebida: {sessao}")
                    break
            continue
        tempos = [t for top in CADEIA for t, m in bus.recebidas.get(top, []) if m.get("session_id") == sessao]
        ultimo = max(tempos) if tempos else sessao_em
        if tempos and time.monotonic() - ultimo > QUIETO_S:
            log("cadeia quieta; encerrando a observação")
            break
        if not tempos and time.monotonic() - sessao_em > 120:
            log("nenhuma mensagem da cadeia 120 s depois da sessão")
            break

    if sessao is None:
        registrar("C01", "Sessão do vídeo (ods.session.started do P4)", FALHOU,
                  f"nenhuma sessão de {SOURCE_ID} em {ESPERA_SESSAO_S} s")
    else:
        registrar("C01", "Sessão do vídeo (ods.session.started do P4)", PASSOU, sessao)

    # Métricas do S5: a janela de 1 minuto precisa fechar.
    if sessao:
        minuto = (sessao_inicio or inicio).replace(second=0, microsecond=0)
        limite = time.monotonic() + ESPERA_METRICAS_S
        while time.monotonic() < limite:
            bus.receber(0.5)
            if any((m.get("payload") or {}).get("zone_id") in ZONAS
                   and (ler_iso((m.get("payload") or {}).get("window_end_at")) or minuto) > minuto
                   for _, m in bus.recebidas.get("ods.s5.zone_metrics", [])):
                break

    def contar(topico: str) -> list[dict]:
        return bus.da_sessao(topico, sessao) if sessao else []

    elos = [
        ("C02", "Detecções do I1 na sessão", "ods.i1.detections"),
        ("C03", "Trilhas do I2 na sessão", "ods.i2.tracks"),
        ("C04", "Posições do S1 na sessão", "ods.s1.position"),
    ]
    for cod, desc, top in elos:
        n = len(contar(top))
        registrar(cod, desc, PASSOU if n else FALHOU, f"{n} mensagem(ns)")

    trans = contar("ods.s1.zone_transition")
    zonas_vistas = sorted({(m.get("payload") or {}).get("zone_id") for m in trans} - {None})
    fora = [z for z in zonas_vistas if z not in ZONAS]
    if trans and not fora:
        registrar("C05", "Entradas e saídas de vaga (S1)", PASSOU, f"{len(trans)} transição(ões) em {', '.join(zonas_vistas)}")
    elif trans:
        registrar("C05", "Entradas e saídas de vaga (S1)", FALHOU, f"zonas fora do artefato: {', '.join(fora)}")
    else:
        registrar("C05", "Entradas e saídas de vaga (S1)", FALHOU, "nenhuma transição na sessão")

    ocup = contar("ods.s1.zone_occupancy")
    registrar("C06", "Ocupação das vagas (S1)", PASSOU if ocup else FALHOU, f"{len(ocup)} mensagem(ns)")

    metr = [m for _, m in bus.recebidas.get("ods.s5.zone_metrics", []) if (m.get("payload") or {}).get("zone_id") in ZONAS]
    registrar("C07", "Métricas por vaga publicadas (S5)", PASSOU if metr else FALHOU,
              f"{len(metr)} janela(s) recebida(s)")

    placas = [m for _, m in bus.recebidas.get("ods.i7.plate_read", [])]
    if placas:
        lidas = sorted({(m.get("payload") or {}).get("license_plate") for m in placas} - {None})
        registrar("C08", "Leituras de placa (I7)", PASSOU, f"{len(placas)} leitura(s): {', '.join(lidas[:8])}")
        ligadas = [m for m in placas if m.get("session_id") == sessao and (m.get("payload") or {}).get("detection_id") is not None]
        registrar("C09", "Placa ligada ao veículo rastreado (I7 citando detection_id do I1)",
                  PASSOU if ligadas else AVISO,
                  "" if ligadas else "o I7 lê imagens soltas, não os quadros do P4; sem detection_id da sessão")
    else:
        registrar("C08", "Leituras de placa (I7)", FALHOU, "nenhuma ods.i7.plate_read recebida")

    eventos_s2 = bus.recebidas.get("ods.s2.event", [])
    registrar("C10", "Eventos qualificados (S2)", PASSOU if eventos_s2 else BLOQUEADO,
              "" if eventos_s2 else "o S2 ainda não publica no Kafka")

    # 4. Pedidos do A8 -------------------------------------------------------------
    fim = agora() + timedelta(minutes=1)
    ini = ((sessao_inicio or inicio) - timedelta(minutes=5)).replace(second=0, microsecond=0)
    periodo = {"period_start_at": iso(ini), "period_end_at": iso(fim.replace(second=0, microsecond=0))}

    _, resp = bus.pedir("ods.s5.metrics.query", "S5",
                        {"metric": "ZONE", "zone_id": ZONAS[0], "granularity": "1m", **periodo},
                        ["ods.s5.metrics.reply"])
    if not resp:
        registrar("C11", f"Série de métricas da {ZONAS[0]} (ods.s5.metrics.query)", FALHOU, "sem resposta")
    else:
        p = resp[0][1].get("payload") or {}
        serie = p.get("series") or []
        com_dados = [s for s in serie if (s.get("total_count") or 0) > 0 or (s.get("occupancy_peak") or 0) > 0]
        if p.get("status") == "OK" and com_dados:
            registrar("C11", f"Série de métricas da {ZONAS[0]} (ods.s5.metrics.query)", PASSOU,
                      f"{len(serie)} janela(s), {len(com_dados)} com movimento")
        elif p.get("status") == "OK":
            registrar("C11", f"Série de métricas da {ZONAS[0]} (ods.s5.metrics.query)", AVISO,
                      f"{len(serie)} janela(s), nenhuma com movimento")
        else:
            registrar("C11", f"Série de métricas da {ZONAS[0]} (ods.s5.metrics.query)", FALHOU,
                      json.dumps(p.get("error"), ensure_ascii=False))

    _, resp = bus.pedir("ods.s5.heatmap.query", "S5",
                        {"source_id": SOURCE_ID, "cell_size_px": 40, **periodo},
                        ["ods.s5.heatmap.reply"])
    if not resp:
        registrar("C12", "Mapa de calor em pixels (ods.s5.heatmap.query)", FALHOU, "sem resposta")
    else:
        p = resp[0][1].get("payload") or {}
        celulas = sum(1 for linha in (p.get("cells") or []) for v in linha if v)
        estado = PASSOU if p.get("status") == "OK" and (celulas or p.get("heatmap_uri")) else (
            AVISO if p.get("status") == "OK" else FALHOU)
        registrar("C12", "Mapa de calor em pixels (ods.s5.heatmap.query)", estado,
                  f"status {p.get('status')}, {celulas} célula(s) com presença" if p.get("status") == "OK"
                  else json.dumps(p.get("error"), ensure_ascii=False))

    # S4: o a8.sh reinicia o S4 depois do vídeo; esperamos o buffer encher de novo.
    limite = time.monotonic() + ESPERA_BUFFER_S4_S
    stats = buffer_s4()
    while time.monotonic() < limite and not (stats and stats.get("has_frames")):
        bus.receber(1.0)
        stats = buffer_s4()
    clip_id = None
    if not (stats and stats.get("has_frames")):
        registrar("C13", "Clipe pedido ao S4 (ods.s4.capture.command)", FALHOU,
                  "o buffer do S4 continua vazio" if stats else f"S4 não respondeu em {S4_HTTP}")
    else:
        agora_ = agora()
        mid, resp = bus.pedir("ods.s4.capture.command", "S4",
                              {"source_id": SOURCE_ID, "media_type": "CLIP",
                               "start_at": iso(agora_ - timedelta(seconds=5)), "end_at": iso(agora_),
                               "event_id": None, "label": "aceite-a8"},
                              ["ods.s4.capture.reply"], espera_s=ESPERA_RESPOSTA_S + 15, todas=True)
        limite = time.monotonic() + 30
        clipes: list[dict] = []
        while time.monotonic() < limite:
            bus.receber(0.5)
            clipes = [m for _, m in bus.recebidas.get("ods.s4.clip", []) if m.get("correlation_id") == mid]
            if clipes:
                break
        erros = [m for _, m in resp if (m.get("payload") or {}).get("status") == "ERROR"]
        oks = [m for _, m in resp if (m.get("payload") or {}).get("status") == "OK"]
        if clipes:
            p = clipes[0].get("payload") or {}
            clip_id = p.get("clip_id")
            registrar("C13", "Clipe pedido ao S4 (ods.s4.capture.command)", PASSOU,
                      f"resposta OK e ods.s4.clip {clip_id} ({p.get('start_at')} a {p.get('end_at')})")
        elif erros:
            registrar("C13", "Clipe pedido ao S4 (ods.s4.capture.command)", FALHOU,
                      json.dumps((erros[0].get("payload") or {}).get("error"), ensure_ascii=False))
        elif oks:
            registrar("C13", "Clipe pedido ao S4 (ods.s4.capture.command)", FALHOU,
                      "resposta OK, mas nenhum ods.s4.clip correlacionado em 30 s")
        else:
            registrar("C13", "Clipe pedido ao S4 (ods.s4.capture.command)", FALHOU, "sem resposta")

        if clipes:
            fim_c = ler_iso((clipes[0].get("payload") or {}).get("end_at"))
            if fim_c and abs((fim_c - agora()).total_seconds()) > 6 * 3600:
                registrar("C14", "Data e hora do clipe coerentes com o relógio", FALHOU,
                          f"end_at {iso(fim_c)} está a {(fim_c - agora()).total_seconds() / 3600:.1f} h de agora")
            else:
                registrar("C14", "Data e hora do clipe coerentes com o relógio", PASSOU)

    if clip_id:
        _, resp = bus.pedir("ods.s4.clip.query", "S4", {"clip_id": clip_id},
                            ["ods.s4.clip.reply", "ods.s4.clip.query.reply"])
        if not resp:
            registrar("C15", "Descritor do clipe (ods.s4.clip.query)", FALHOU, "sem resposta")
        else:
            topico, m = resp[0]
            p = m.get("payload") or {}
            achou = any(c.get("clip_id") == clip_id for c in (p.get("clips") or []))
            if p.get("status") == "OK" and achou and topico == "ods.s4.clip.reply":
                registrar("C15", "Descritor do clipe (ods.s4.clip.query)", PASSOU)
            elif p.get("status") == "OK" and achou:
                registrar("C15", "Descritor do clipe (ods.s4.clip.query)", AVISO,
                          f"resposta certa, mas em {topico}; a especificação define ods.s4.clip.reply")
            else:
                registrar("C15", "Descritor do clipe (ods.s4.clip.query)", FALHOU,
                          f"status {p.get('status')}, clipe {'encontrado' if achou else 'ausente'}")

    _, resp = bus.pedir("ods.s2.rules.command", "S2", {
        "artifact_version": "rules-a8-aceite",
        "rules": [{"rule_id": "a8-aceite-ocupacao", "event_type": "OCCUPANCY_ABOVE", "zone_id": ZONAS[0],
                   "min_confidence": 0.5, "uncertain_below": 0.7, "min_duration_ms": 500,
                   "debounce_ms": 1000, "threshold": 0}],
    }, ["ods.s2.rules.reply"], espera_s=15)
    if resp:
        p = resp[0][1].get("payload") or {}
        registrar("C16", "Regras enviadas ao S2 (ods.s2.rules.command)",
                  PASSOU if p.get("status") == "OK" else FALHOU, json.dumps(p, ensure_ascii=False)[:120])
    else:
        registrar("C16", "Regras enviadas ao S2 (ods.s2.rules.command)", BLOQUEADO,
                  "sem resposta: o S2 ainda não está no Kafka")

    registrar("C17", "Calibração do I3", BLOQUEADO,
              "zonas em pixels; a calibração só entra com zonas em metros e medidas reais")

    # 5. Contrato (envelope 1.0, validador do B4) -----------------------------------
    if validate_message is None:
        registrar("C18", "Envelope 1.0 de todas as mensagens (validador do B4)", BLOQUEADO,
                  f"validador não encontrado em {B4_DIR}")
        por_schema = {}
    else:
        por_schema = {}
        for topico, lista in bus.recebidas.items():
            if topico not in CONTRATOS:
                continue
            tipo, produtor, campos, contexto = CONTRATOS[topico]
            for _, m in lista:
                if topico in ("ods.session.started", "ods.i1.detections", "ods.i2.tracks",
                              "ods.s1.position", "ods.s1.zone_transition", "ods.s1.zone_occupancy") \
                        and m.get("session_id") != sessao and not (topico == "ods.session.started" and eh_da_fonte(m)):
                    continue  # mensagens de outras equipes ou sessões não entram na conta
                erros = validate_message(m, schema=topico, message_type=tipo, producer=produtor,
                                         payload_fields=campos, context_fields=contexto)
                r = por_schema.setdefault(topico, {"total": 0, "invalidas": 0, "erros": []})
                r["total"] += 1
                if erros:
                    r["invalidas"] += 1
                    for e in erros:
                        if e not in r["erros"] and len(r["erros"]) < 4:
                            r["erros"].append(e)
        ruins = {k: v for k, v in por_schema.items() if v["invalidas"]}
        if not por_schema:
            registrar("C18", "Envelope 1.0 de todas as mensagens (validador do B4)", FALHOU, "nada para validar")
        elif not ruins:
            registrar("C18", "Envelope 1.0 de todas as mensagens (validador do B4)", PASSOU,
                      f"{sum(v['total'] for v in por_schema.values())} mensagem(ns) em {len(por_schema)} schema(s)")
        else:
            resumo = "; ".join(f"{k}: {v['invalidas']}/{v['total']} ({v['erros'][0]})" for k, v in sorted(ruins.items()))
            registrar("C18", "Envelope 1.0 de todas as mensagens (validador do B4)", FALHOU, resumo)
    if bus.invalidas:
        registrar("C19", "Mensagens que não são JSON", FALHOU,
                  f"{len(bus.invalidas)} em {', '.join(sorted({t for t, _ in bus.invalidas}))}")

    # Relatório ---------------------------------------------------------------------
    contagem = {k: sum(1 for i in itens if i["resultado"] == k) for k in (PASSOU, FALHOU, BLOQUEADO, AVISO)}
    amostras = {t: lista[0][1] for t, lista in bus.recebidas.items() if lista}
    carimbo = agora().strftime("%Y%m%d-%H%M%S")
    relatorio = {
        "teste": "aceite-a8", "inicio": iso(inicio), "fim": iso(agora()), "broker": BROKER,
        "fonte": SOURCE_ID, "zonas": ZONAS, "sessao": sessao, "resumo": contagem, "itens": itens,
        "contrato_por_schema": por_schema,
        "mensagens_recebidas": {t: len(l) for t, l in sorted(bus.recebidas.items())},
        "amostras": amostras,
    }
    linhas = [f"Teste de aceitação do A8 — {iso(inicio)}  (sessão {sessao})", ""]
    linhas += [f"{i['item']}  {i['resultado']:9}  {i['verificacao']}" + (f"\n                  {i['detalhe']}" if i["detalhe"] else "")
               for i in itens]
    linhas += ["", "Resumo: " + "  ".join(f"{k} {v}" for k, v in contagem.items())]
    os.makedirs(RESULT_DIR, exist_ok=True)
    base = os.path.join(RESULT_DIR, f"aceite-a8-{carimbo}")
    with open(base + ".json", "w", encoding="utf-8") as f:
        json.dump(relatorio, f, ensure_ascii=False, indent=2)
    with open(base + ".txt", "w", encoding="utf-8") as f:
        f.write("\n".join(linhas) + "\n")
    print("\n" + "\n".join(linhas), flush=True)
    log(f"relatório gravado em {base}.txt e .json")
    bus.consumer.close()
    return 1 if contagem[FALHOU] else 0


if __name__ == "__main__":
    sys.exit(main())
