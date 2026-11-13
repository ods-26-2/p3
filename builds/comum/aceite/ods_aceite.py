"""Biblioteca comum dos testes de aceitação das builds ODS (P3 / SIS-1).

Extraída do teste do A8 (builds/a8/aceite/aceite_a8.py, validado no Kafka da turma) para os
testes de A1 a A7. Cada teste faz, pelo Kafka da turma, o papel que a Especificação de
interfaces 1.0 (6c) dá à aplicação: escuta o que ela consome, faz os pedidos que ela faz,
confere as respostas e valida o envelope de cada mensagem com o validador do B4
(tests/integration/contract_validation.py).

Estados de um item:
  PASSOU     o elo funcionou
  FALHOU     o elo deveria funcionar com o que está na build e não funcionou
  BLOQUEADO  depende de algo que ainda não existe (ex.: S2 no Kafka, P7) — não reprova
  AVISO      funciona, mas fora da 6c ou com ressalva — não reprova
Quando o teste precisa injetar uma mensagem porque o produtor real não existe na build,
a descrição do item diz "(entrada simulada: <componente>)".

Saída do teste: 0 se nenhum item FALHOU, 1 caso contrário.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from typing import Callable, Iterable

from confluent_kafka import OFFSET_END, Consumer, KafkaError, Producer

BROKER = os.environ["KAFKA_BROKER"]
RESULT_DIR = os.environ.get("RESULT_DIR", "/resultados")
B4_DIR = os.environ.get("B4_DIR", "/b4")
ESPERA_RESPOSTA_S = int(os.environ.get("ESPERA_RESPOSTA_S", "20"))
# Multiplica todas as esperas (ex.: 2 numa placa lenta; 0.05 nos testes do próprio P3).
FATOR_TEMPO = float(os.environ.get("ACEITE_FATOR_TEMPO", "1"))

PASSOU, FALHOU, BLOQUEADO, AVISO = "PASSOU", "FALHOU", "BLOQUEADO", "AVISO"

# Perfis de envelope da seção 3 da especificação 1.0.
EV_SINAL = ("captured_at", "source_id", "session_id", "sequence", "artifact_version")
EV_SINAL_SEM_ARTEFATO = ("captured_at", "source_id", "session_id", "sequence")
EV_SERVICO = ("captured_at", "session_id", "sequence")
CMD = ("target",)
RPL = ("correlation_id",)

# schema -> (message_type, producer, campos do payload, campos de contexto do envelope).
# Payload: os campos obrigatórios das tabelas da especificação 1.0.
CONTRATOS: dict[str, tuple[str, str, tuple[str, ...], tuple[str, ...]]] = {
    "ods.session.started": ("event", "P4", ("mode", "started_at", "sources"), EV_SINAL_SEM_ARTEFATO),
    "ods.i1.detections": ("event", "I1", ("frame_index", "image_width", "image_height", "detections"), EV_SINAL),
    "ods.i2.tracks": ("event", "I2", ("frame_index", "tracks"), EV_SINAL),
    "ods.i3.calibration": ("event", "I3", ("valid_from", "image_width", "image_height", "intrinsics",
                                           "distortion", "homography_px_to_m", "reference_frame",
                                           "reprojection_rms_cm", "holdout_points"),
                           ("source_id", "artifact_version")),
    "ods.i4.sign": ("event", "I4", ("sign", "confidence", "start_at", "end_at"), EV_SINAL),
    "ods.i5.transcript": ("event", "I5", ("start_at", "end_at", "transcribed_text", "normalized_text",
                                          "confidence", "uncertain"), EV_SINAL),
    "ods.i6.code_read": ("event", "I6", ("frame_index", "code_type", "decoded_data", "bbox"), EV_SINAL),
    "ods.i9.ppe_compliance": ("event", "I9", ("frame_index", "detection_id", "bbox", "calibrated",
                                              "catalog_version", "items", "uncertain"), EV_SINAL),
    "ods.s1.position": ("event", "S1", ("frame_index", "positions"), EV_SINAL),
    "ods.s1.zone_transition": ("event", "S1", ("track_id", "class", "zone_id", "transition", "entered_at"), EV_SINAL),
    "ods.s1.zone_occupancy": ("event", "S1", ("zone_id", "count", "count_by_class", "track_ids"), EV_SINAL),
    "ods.s3.alert": ("event", "S3", ("alert_id", "title", "message", "severity", "recipients", "channels",
                                     "state", "created_at"), EV_SERVICO),
    "ods.s4.clip": ("event", "S4", ("clip_id", "media_type", "media_uri", "start_at", "end_at",
                                    "hash_sha256", "expires_at"), EV_SERVICO),
    "ods.s5.zone_metrics": ("event", "S5", ("zone_id", "window_start_at", "window_end_at", "granularity",
                                            "total_count", "occupancy_peak", "occupancy_avg", "dwell_avg_s"), EV_SERVICO),
    "ods.p7.move.command": ("command", "A4", ("source_id", "pan_deg", "tilt_deg"), CMD),
    "ods.s3.alert.command": ("command", "?", ("title", "message", "severity", "recipients", "channels"), CMD),
    "ods.s4.capture.command": ("command", "?", ("source_id", "media_type"), CMD),
    "ods.s6.synthesis.command": ("command", "A6", ("glosses", "speed_factor", "lexicon_version"), CMD),
    "ods.s3.alert.reply": ("reply", "S3", ("status",), RPL),
    "ods.s3.alert_action.reply": ("reply", "S3", ("status",), RPL),
    "ods.s3.alerts.reply": ("reply", "S3", ("status",), RPL),
    "ods.s4.capture.reply": ("reply", "S4", ("status",), RPL),
    "ods.s4.clip.reply": ("reply", "S4", ("status",), RPL),
    "ods.s4.clip.query.reply": ("reply", "S4", ("status",), RPL),
    "ods.s6.synthesis.reply": ("reply", "S6", ("status",), RPL),
}


# ----------------------------------------------------------------------------- utilidades

def agora() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime | None = None) -> str:
    dt = (dt or agora()).astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def ler_iso(valor: object) -> datetime | None:
    if not isinstance(valor, str):
        return None
    try:
        return datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except ValueError:
        return None


def log(texto: str) -> None:
    print(f"[aceite {datetime.now().strftime('%H:%M:%S')}] {texto}", flush=True)


def payload(msg: dict) -> dict:
    p = msg.get("payload")
    return p if isinstance(p, dict) else {}


def http(metodo: str, url: str, corpo: object = None, cabecalhos: dict | None = None,
         timeout: float = 10) -> tuple[int, object]:
    """Pedido HTTP simples. Devolve (código, corpo JSON ou texto); código 0 = sem conexão."""
    dados = json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(url, data=dados, method=metodo)
    req.add_header("Accept", "application/json")
    if dados is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (cabecalhos or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            bruto, codigo = r.read(), r.status
    except urllib.error.HTTPError as e:
        bruto, codigo = e.read(), e.code
    except Exception as e:  # noqa: BLE001 - qualquer falha de conexão vira código 0
        return 0, str(e)
    try:
        return codigo, json.loads(bruto)
    except ValueError:
        return codigo, bruto.decode("utf-8", "replace")


def envelope(schema: str, message_type: str, producer: str, corpo: dict, **contexto) -> dict:
    """Envelope 1.0 (seção 3). Contexto: target, correlation_id, captured_at, source_id,
    session_id, sequence, artifact_version — só os que forem passados."""
    env = {
        "message_type": message_type,
        "message_id": str(uuid.uuid4()),
        "schema": schema,
        "schema_version": "1.0",
        "producer": producer,
        "published_at": iso(),
    }
    env.update({k: v for k, v in contexto.items() if v is not None})
    env["payload"] = corpo
    return env


# ----------------------------------------------------------------------------- barramento

class Barramento:
    """Consumidor que começa no fim de cada tópico e guarda tudo o que recebe."""

    def __init__(self, papel: str) -> None:
        self.papel = papel
        self.recebidas: dict[str, list[tuple[float, dict]]] = defaultdict(list)
        self.invalidas: list[tuple[str, str]] = []
        self._atribuidos: set[str] = set()
        self.consumer = Consumer({
            "bootstrap.servers": BROKER,
            "group.id": f"aceite-{papel.lower()}-{uuid.uuid4()}",
            "enable.auto.commit": False,
            "auto.offset.reset": "latest",
        })
        self.producer = Producer({"bootstrap.servers": BROKER, "acks": "all"})

    def assinar(self, topicos: Iterable[str], espera_s: int = 60) -> list[str]:
        topicos = sorted(set(topicos))

        def ao_atribuir(consumer, particoes):
            for p in particoes:
                p.offset = OFFSET_END
                self._atribuidos.add(p.topic)
            consumer.assign(particoes)

        self.consumer.subscribe(topicos, on_assign=ao_atribuir)
        limite = time.monotonic() + espera_s
        while time.monotonic() < limite and not set(topicos) <= self._atribuidos:
            self.receber(0.5)
        for _ in range(6):  # deixa as posições de fim serem resolvidas antes do PRONTO
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

    def publicar(self, env: dict) -> str:
        self.producer.produce(env["schema"], json.dumps(env).encode("utf-8"),
                              key=str(env.get("message_id")).encode())
        self.producer.flush(10)
        return env["message_id"]

    def mensagens(self, topico: str, filtro: Callable[[dict], bool] | None = None) -> list[dict]:
        return [m for _, m in self.recebidas.get(topico, []) if filtro is None or filtro(m)]

    def esperar(self, condicao: Callable[[], object], espera_s: float) -> object:
        """Recebe até a condição dar verdadeiro ou o tempo acabar; devolve o último valor."""
        limite = time.monotonic() + espera_s * FATOR_TEMPO
        valor = condicao()
        while not valor and time.monotonic() < limite:
            self.receber(0.5)
            valor = condicao()
        return valor

    def correlacionadas(self, topicos: Iterable[str], mid: str) -> list[tuple[str, dict]]:
        return [(t, m) for t in topicos for _, m in self.recebidas.get(t, [])
                if m.get("correlation_id") == mid]

    def pedir(self, schema: str, alvo: str, corpo: dict, topicos_resposta: list[str],
              espera_s: int = ESPERA_RESPOSTA_S) -> tuple[str, list[tuple[str, dict]]]:
        """Envia query/command (perfil CMD) como o papel do teste e espera a reply correlacionada."""
        tipo = "command" if schema.endswith(".command") else "query"
        mid = self.publicar(envelope(schema, tipo, self.papel, corpo, target=alvo))
        resp = self.esperar(lambda: self.correlacionadas(topicos_resposta, mid), espera_s)
        return mid, resp or []

    def fechar(self) -> None:
        try:
            self.consumer.close()
        except Exception:  # noqa: BLE001
            pass


# ----------------------------------------------------------------------------- teste

class Teste:
    def __init__(self, app: str, descricao: str) -> None:
        self.app = app
        self.descricao = descricao
        self.inicio = agora()
        self.itens: list[dict] = []
        self.por_schema: dict[str, dict] = {}
        self.extras: dict[str, object] = {}
        try:
            sys.path.insert(0, B4_DIR)
            from contract_validation import validate_message  # type: ignore
            self.validar = validate_message
        except ImportError:
            self.validar = None

    def registrar(self, cod: str, descricao: str, estado: str, detalhe: str = "") -> None:
        self.itens.append({"item": cod, "verificacao": descricao, "resultado": estado, "detalhe": detalhe})
        log(f"{cod} {estado:9} {descricao}" + (f" — {detalhe}" if detalhe else ""))

    def validar_contratos(self, cod: str, bus: Barramento,
                          incluir: Callable[[str, dict], bool] | None = None,
                          produtores: dict[str, str] | None = None) -> None:
        """Valida o envelope 1.0 de tudo o que foi recebido nos tópicos de CONTRATOS.
        incluir(topico, msg) filtra (ex.: só a sessão do teste); produtores sobrescreve o
        produtor esperado por tópico (comandos podem vir de várias aplicações)."""
        desc = "Envelope 1.0 das mensagens recebidas (validador do B4)"
        if self.validar is None:
            self.registrar(cod, desc, BLOQUEADO, f"validador não encontrado em {B4_DIR}")
            return
        produtores = produtores or {}
        for topico, lista in bus.recebidas.items():
            if topico not in CONTRATOS:
                continue
            tipo, produtor, campos, contexto = CONTRATOS[topico]
            produtor = produtores.get(topico, produtor)
            for _, m in lista:
                if incluir and not incluir(topico, m):
                    continue
                if produtor == "?":
                    produtor_msg = m.get("producer")
                else:
                    produtor_msg = produtor
                erros = self.validar(m, schema=topico, message_type=tipo, producer=produtor_msg,
                                     payload_fields=campos, context_fields=contexto)
                r = self.por_schema.setdefault(topico, {"total": 0, "invalidas": 0, "erros": []})
                r["total"] += 1
                if erros:
                    r["invalidas"] += 1
                    for e in erros:
                        if e not in r["erros"] and len(r["erros"]) < 4:
                            r["erros"].append(e)
        ruins = {k: v for k, v in self.por_schema.items() if v["invalidas"]}
        if not self.por_schema:
            self.registrar(cod, desc, FALHOU, "nada para validar")
        elif not ruins:
            self.registrar(cod, desc, PASSOU, f"{sum(v['total'] for v in self.por_schema.values())} "
                                              f"mensagem(ns) em {len(self.por_schema)} schema(s)")
        else:
            resumo = "; ".join(f"{k}: {v['invalidas']}/{v['total']} ({v['erros'][0]})"
                               for k, v in sorted(ruins.items()))
            self.registrar(cod, desc, FALHOU, resumo)
        if bus.invalidas:
            self.registrar(cod + "b", "Mensagens que não são JSON", FALHOU,
                           f"{len(bus.invalidas)} em {', '.join(sorted({t for t, _ in bus.invalidas}))}")

    def concluir(self, bus: Barramento | None = None) -> int:
        contagem = {k: sum(1 for i in self.itens if i["resultado"] == k)
                    for k in (PASSOU, FALHOU, BLOQUEADO, AVISO)}
        carimbo = agora().strftime("%Y%m%d-%H%M%S")
        relatorio = {
            "teste": f"aceite-{self.app}", "descricao": self.descricao,
            "inicio": iso(self.inicio), "fim": iso(), "broker": BROKER,
            "resumo": contagem, "itens": self.itens, "contrato_por_schema": self.por_schema,
            **self.extras,
        }
        if bus is not None:
            relatorio["mensagens_recebidas"] = {t: len(l) for t, l in sorted(bus.recebidas.items())}
            relatorio["amostras"] = {t: l[0][1] for t, l in bus.recebidas.items() if l}
        linhas = [f"Teste de aceitação do {self.app.upper()} — {iso(self.inicio)}", self.descricao, ""]
        linhas += [f"{i['item']:4}  {i['resultado']:9}  {i['verificacao']}"
                   + (f"\n                  {i['detalhe']}" if i["detalhe"] else "") for i in self.itens]
        linhas += ["", "Resumo: " + "  ".join(f"{k} {v}" for k, v in contagem.items())]
        os.makedirs(RESULT_DIR, exist_ok=True)
        base = os.path.join(RESULT_DIR, f"aceite-{self.app}-{carimbo}")
        with open(base + ".json", "w", encoding="utf-8") as f:
            json.dump(relatorio, f, ensure_ascii=False, indent=2, default=str)
        with open(base + ".txt", "w", encoding="utf-8") as f:
            f.write("\n".join(linhas) + "\n")
        print("\n" + "\n".join(linhas), flush=True)
        log(f"relatório gravado em {base}.txt e .json")
        if bus is not None:
            bus.fechar()
        return 1 if contagem[FALHOU] else 0


def pausa(segundos: float) -> None:
    time.sleep(segundos * FATOR_TEMPO)


def pronto(bus: Barramento, topicos: Iterable[str], papel: str) -> None:
    """Assina os tópicos e escreve a linha PRONTO que o <app>.sh espera para seguir."""
    faltando = bus.assinar(topicos)
    if faltando:
        log(f"tópicos sem partição atribuída (não existem no broker?): {', '.join(faltando)}")
    log(f"PRONTO — escutando {BROKER} como {papel}")


def esperar_passo(bus: Barramento, nome: str, espera_s: int = 900) -> bool:
    """Espera o <app>.sh criar /resultados/.passo-<nome> (sinal de que um passo externo,
    como tocar o vídeo, terminou), recebendo mensagens enquanto isso (sem poll por mais de
    5 min o consumidor sairia do grupo). Devolve False se o tempo acabar."""
    marca = os.path.join(RESULT_DIR, f".passo-{nome}")
    log(f"esperando o passo externo '{nome}'")
    limite = time.monotonic() + espera_s * FATOR_TEMPO
    while time.monotonic() < limite:
        if os.path.exists(marca):
            try:
                os.remove(marca)
            except OSError:
                pass
            return True
        bus.receber(1.0)
    return False
