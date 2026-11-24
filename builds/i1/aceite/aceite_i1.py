"""Teste de aceitação da build dedicada do I1 (P3 / SIS-1).

Faz, pelo Kafka da turma, o papel das aplicações que pedem detecção ao I1: manda comandos em
ods.i1.command e confere o que sai em ods.i1.detections. Roda dentro da imagem do I1 (sem GPU),
então usa o mesmo mapa equipe -> pacote do orquestrador (detector.orchestrator.APP_PROFILES).

Roteiro (cada pedido usa um source_id "p3-teste-*" e um session_id próprio, para não se
misturar com aplicações reais):
  T01  tópicos do I1 existem no broker
  T02  comandos inválidos (JSON quebrado, equipe desconhecida) são ignorados   [conferido no log]
  T1x  carga de cada pacote: um START por equipe, todos de uma vez (fila FIFO)
       artifact_version "<pacote>-fp16" (TensorRT), classes do pacote, schema do I1, sequence
  T20  fila FIFO: as equipes foram atendidas na ordem, uma por vez, sem mistura
  T21  tempo de troca de modelo (fim de uma equipe -> primeira detecção da seguinte)
  T22  envelope 1.0 (validador do B4)
  T30  pedido com vídeo inexistente: o I1 registra o erro e segue atendendo     [log]
  T31  STOP interrompe a equipe ativa
  T32  sem HEARTBEAT, o pedido expira no TTL
  T33  com HEARTBEAT, o pedido vai até o fim do vídeo
  T40  motivos de encerramento no log batem com o esperado                     [log]
  T41  o serviço não reiniciou durante o teste                                 [log]
  T42  sem falta de memória da GPU (OUT_OF_MEMORY / NvMap error 12)            [log]

O log do container i1 chega pelo passo externo "log": o i1.sh grava /resultados/.i1-log.txt.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import uuid

sys.path.insert(0, os.environ.get("ODS_ACEITE_COMUM", "/comum"))
from ods_aceite import (AVISO, BLOQUEADO, FALHOU, PASSOU, Barramento, Teste,  # noqa: E402
                        esperar_passo, ler_iso, log)

try:
    from detector.orchestrator import APP_PROFILES  # imagem do I1: /app/I1 no PYTHONPATH
except Exception as erro:  # noqa: BLE001
    print(f"não consegui ler os perfis do orquestrador do I1: {erro}", flush=True)
    sys.exit(2)

TOPICO_CMD = os.environ.get("I1_COMMAND_TOPIC", "ods.i1.command")
TOPICO_DET = "ods.i1.detections"
PACOTES = os.environ.get("I1_PACOTES", "").split()
QUADROS = int(os.environ.get("I1_TESTE_QUADROS", "30"))
# Exceções por equipe ("INV1=150"): no INV1.mp4 a bola só aparece por volta do quadro 120.
QUADROS_EQUIPE = {k: int(v) for k, v in (par.split("=", 1) for par in
                  os.environ.get("I1_TESTE_QUADROS_EQUIPE", "").split() if "=" in par)}
VIDEOS_DIR = os.environ.get("I1_TESTE_VIDEOS_DIR", "/videos")
ARTEFATOS = os.environ.get("I1_ARTEFATOS", "/app/I1/artifacts")
SCHEMA_I1 = os.environ.get("I1_SCHEMA", "/app/schemas/ods.i1.detections.v1.0.schema.json")
ESPERA_PRIMEIRA_S = int(os.environ.get("I1_ESPERA_PRIMEIRA_S", "180"))
SILENCIO_FIM_S = float(os.environ.get("I1_SILENCIO_FIM_S", "4"))
TTL_CURTO_S = 4

VIDEOS = dict(par.split("=", 1) for par in os.environ.get("I1_TESTE_VIDEOS", "").split() if "=" in par)
PERFIS = {p.squad: p for p in APP_PROFILES}


# ----------------------------------------------------------------------------- apoio

def comando(bus: Barramento, corpo: dict | str, chave: str = "p3-teste") -> None:
    valor = corpo if isinstance(corpo, str) else json.dumps(corpo)
    bus.producer.produce(TOPICO_CMD, valor.encode("utf-8"), key=chave.encode())
    bus.producer.flush(10)


def start(bus: Barramento, squad: str, fonte: str, rotulo: str, **extra) -> dict:
    pedido = {
        "squad": squad, "fonte": fonte, "source_id": f"p3-teste-{rotulo}",
        "session_id": str(uuid.uuid4()), "enviado": time.monotonic(),
    }
    corpo = {"action": "START", "squad": squad, "source": fonte,
             "source_id": pedido["source_id"], "session_id": pedido["session_id"]}
    corpo.update(extra)
    comando(bus, corpo, squad)
    log(f"START {squad} ({rotulo}): {json.dumps(corpo)}")
    return pedido


def msgs(bus: Barramento, pedido: dict) -> list[tuple[float, dict]]:
    return [(t, m) for t, m in bus.recebidas.get(TOPICO_DET, []) if m.get("session_id") == pedido["session_id"]]


def esperar_fim(bus: Barramento, pedido: dict, espera_primeira: float = ESPERA_PRIMEIRA_S,
                silencio: float = SILENCIO_FIM_S, teto: float = 300) -> list[tuple[float, dict]]:
    """Espera a primeira mensagem do pedido e depois 'silencio' segundos sem mensagens novas."""
    bus.esperar(lambda: msgs(bus, pedido), espera_primeira)
    limite = time.monotonic() + teto
    while msgs(bus, pedido) and time.monotonic() < limite:
        ultima = msgs(bus, pedido)[-1][0]
        if time.monotonic() - ultima >= silencio:
            break
        bus.receber(0.5)
    return msgs(bus, pedido)


def video_de(squad: str) -> tuple[str | None, bool]:
    """(caminho do vídeo no container, é vídeo próprio da equipe?)"""
    proprio = VIDEOS.get(squad)
    if proprio and os.path.isfile(os.path.join(VIDEOS_DIR, proprio)):
        return os.path.join(VIDEOS_DIR, proprio), True
    reserva = VIDEOS.get("VER5")
    if reserva and os.path.isfile(os.path.join(VIDEOS_DIR, reserva)):
        return os.path.join(VIDEOS_DIR, reserva), False
    return None, False


def classes_do_pacote(perfil) -> set[str]:
    with open(f"{ARTEFATOS}/{perfil.artifact_id}/{perfil.artifact_version}/metadata.json", encoding="utf-8") as f:
        classes = {str(c) for c in json.load(f)["classes"]}
    return set(perfil.enabled_classes) & classes if perfil.enabled_classes else classes


def carregar_validador_i1():
    try:
        import jsonschema
        with open(SCHEMA_I1, encoding="utf-8") as f:
            schema = json.load(f)
        cls = jsonschema.validators.validator_for(schema)
        return cls(schema)
    except Exception as erro:  # noqa: BLE001
        log(f"schema do I1 indisponível: {erro}")
        return None


def instante(m: dict) -> float | None:
    dt = ler_iso(m.get("published_at"))
    return dt.timestamp() if dt else None


# ----------------------------------------------------------------------------- teste

def main() -> int:
    teste = Teste("i1", "Build dedicada do I1: orquestrador FIFO (ods.i1.command) na GPU")
    bus = Barramento("P3-TESTE-I1")
    faltando = bus.assinar([TOPICO_DET, TOPICO_CMD])
    if faltando:
        teste.registrar("T01", "Tópicos do I1 no broker", FALHOU, f"sem partição: {', '.join(faltando)}")
        return teste.concluir(bus)
    teste.registrar("T01", "Tópicos do I1 no broker", PASSOU, f"{TOPICO_CMD}, {TOPICO_DET}")
    log("PRONTO — escutando como aplicação que pede detecção ao I1")

    validador = carregar_validador_i1()
    esperados: list[tuple[str, str, set[str]]] = []   # (equipe, rótulo, motivos aceitos), na ordem
    teste.extras["pedidos"] = []

    # --- T02: comandos inválidos (o I1 deve ignorar e seguir)
    comando(bus, "{isto não é json", "p3-teste")
    comando(bus, {"action": "START", "squad": "P3-EQUIPE-INEXISTENTE"}, "p3-teste")

    # --- T1x: carga de cada pacote, todos os STARTs de uma vez (fila FIFO)
    lote: list[tuple[str, dict, bool, object]] = []
    for squad in ("VER5", "VER3", "VER6", "VER1", "INV1"):
        perfil = PERFIS.get(squad)
        if perfil is None:
            continue
        pacote = f"{perfil.artifact_id}/{perfil.artifact_version}"
        if pacote not in PACOTES:
            teste.registrar(f"T1-{squad}", f"Carga do {perfil.engine_ref} ({squad}/{perfil.app_id})", BLOQUEADO,
                            "pacote fora de I1_PACOTES (sem engine preparada)")
            continue
        fonte, proprio = video_de(squad)
        if fonte is None:
            teste.registrar(f"T1-{squad}", f"Carga do {perfil.engine_ref} ({squad}/{perfil.app_id})", BLOQUEADO,
                            f"sem vídeo em {VIDEOS_DIR} (I1_TESTE_VIDEOS)")
            continue
        pedido = start(bus, squad, fonte, f"carga-{squad.lower()}", max_frames=QUADROS_EQUIPE.get(squad, QUADROS), ttl_seconds=300)
        lote.append((squad, pedido, proprio, perfil))
        esperados.append((squad, f"carga-{squad.lower()}", {"max_frames_reached", "source_completed"}))

    for squad, pedido, proprio, perfil in lote:
        lista = esperar_fim(bus, pedido)
        corpo = [m for _, m in lista]
        desc = f"Carga do {perfil.engine_ref} ({squad}/{perfil.app_id}) na GPU"
        info = {"squad": squad, "fonte": pedido["fonte"], "video_proprio": proprio,
                "session_id": pedido["session_id"], "mensagens": len(corpo)}
        teste.extras["pedidos"].append(info)
        if not corpo:
            teste.registrar(f"T1-{squad}", desc, FALHOU, f"nenhuma detecção em {ESPERA_PRIMEIRA_S} s")
            continue
        versoes = sorted({m.get("artifact_version") for m in corpo})
        esperado = f"{perfil.engine_ref}-fp16"
        permitidas = classes_do_pacote(perfil)
        vistas: dict[str, int] = {}
        for m in corpo:
            for d in (m.get("payload") or {}).get("detections") or []:
                vistas[str(d.get("class"))] = vistas.get(str(d.get("class")), 0) + 1
        estranhas = sorted(set(vistas) - permitidas)
        invalidas = 0
        primeiro_erro = ""
        if validador is not None:
            for m in corpo:
                erros = list(validador.iter_errors(m))
                if erros:
                    invalidas += 1
                    primeiro_erro = primeiro_erro or erros[0].message[:120]
        seqs = [m.get("sequence") for m in corpo]
        buracos = 0
        if all(isinstance(s, int) for s in seqs):
            seqs = sorted(seqs)
            buracos = (seqs[-1] - seqs[0] + 1) - len(seqs)
        espera = lista[0][0] - pedido["enviado"]
        info.update({"artifact_version": versoes, "classes": vistas, "fora_do_pacote": estranhas,
                     "fora_do_schema": invalidas, "lacunas_sequence": buracos,
                     "start_ate_primeira_s": round(espera, 2)})
        detalhe = (f"{len(corpo)} mensagens, artifact_version {versoes}, classes {vistas or '{}'}, "
                   f"1ª mensagem {espera:.1f} s após o START")
        problemas = []
        if versoes != [esperado]:
            problemas.append(f"esperado só {esperado} (TensorRT FP16)")
        if estranhas:
            problemas.append(f"classes fora do pacote: {estranhas}")
        if validador is None:
            problemas.append("schema do I1 não conferido")
        elif invalidas:
            problemas.append(f"{invalidas} fora do schema do I1 ({primeiro_erro})")
        if buracos:
            problemas.append(f"{buracos} lacuna(s) em sequence (quadros descartados)")
        if versoes != [esperado] or estranhas or invalidas:
            teste.registrar(f"T1-{squad}", desc, FALHOU, detalhe + " — " + "; ".join(problemas))
        elif not proprio:
            teste.registrar(f"T1-{squad}", desc, AVISO, detalhe + " — vídeo de outra equipe: prova carga e "
                            "execução na GPU, não a qualidade das detecções" + ("; " + "; ".join(problemas) if problemas else ""))
        elif not vistas:
            teste.registrar(f"T1-{squad}", desc, AVISO, detalhe + f" — nenhum objeto nos {len(corpo)} quadros")
        else:
            teste.registrar(f"T1-{squad}", desc, AVISO if problemas else PASSOU,
                            detalhe + ("; " + "; ".join(problemas) if problemas else ""))

    # --- T20/T21: fila FIFO e tempo de troca
    janelas = []
    for squad, pedido, _, _ in lote:
        tempos = [instante(m) for _, m in msgs(bus, pedido)]
        tempos = [t for t in tempos if t is not None]
        if tempos:
            janelas.append((squad, min(tempos), max(tempos)))
    if len(janelas) < 2:
        teste.registrar("T20", "Fila FIFO: uma equipe por vez, na ordem dos pedidos", BLOQUEADO,
                        "menos de duas equipes com detecções")
    else:
        ordem_ok = [s for s, _, _ in janelas] == [s for s, _, _ in sorted(janelas, key=lambda j: j[1])]
        sobrepostas = [f"{a[0]}/{b[0]}" for a, b in zip(janelas, janelas[1:]) if b[1] < a[2]]
        ordem = " → ".join(s for s, _, _ in sorted(janelas, key=lambda j: j[1]))
        if ordem_ok and not sobrepostas:
            teste.registrar("T20", "Fila FIFO: uma equipe por vez, na ordem dos pedidos", PASSOU, ordem)
        else:
            teste.registrar("T20", "Fila FIFO: uma equipe por vez, na ordem dos pedidos", FALHOU,
                            f"ordem {ordem}; sobrepostas: {sobrepostas or 'nenhuma'}")
        trocas = [(f"{a[0]}→{b[0]}", round(b[1] - a[2], 2)) for a, b in zip(janelas, janelas[1:])]
        teste.extras["trocas_de_modelo_s"] = dict(trocas)
        pior = max(t for _, t in trocas)
        teste.registrar("T21", "Tempo de troca de modelo (libera um, carrega outro)",
                        PASSOU if pior <= 15 else AVISO,
                        ", ".join(f"{k} {v:.1f} s" for k, v in trocas) + (" (acima de 15 s)" if pior > 15 else ""))

    # O JSON quebrado em ods.i1.command é o do T02 (o teste assina o tópico só para conferir que existe).
    bus.invalidas = [(t, e) for t, e in bus.invalidas if t != TOPICO_CMD]
    teste.validar_contratos("T22", bus, incluir=lambda t, m: str(m.get("source_id", "")).startswith("p3-teste-"))

    # --- T30: vídeo inexistente (deve virar "error" no log, sem derrubar o serviço)
    comando(bus, {"action": "START", "squad": "VER1", "source": f"{VIDEOS_DIR}/p3-nao-existe.mp4",
                  "source_id": "p3-teste-erro", "max_frames": 5}, "VER1")
    esperados.append(("VER1", "erro", {"error"}))
    log("START VER1 com vídeo inexistente (espera erro no log)")
    bus.esperar(lambda: False, 5)

    fonte_longa, _ = video_de("VER5")
    if fonte_longa is None or "app-plates/1.0.0" not in PACOTES:
        for cod, desc in (("T31", "STOP interrompe a equipe ativa"), ("T32", "Sem HEARTBEAT, o pedido expira no TTL"),
                          ("T33", "Com HEARTBEAT, o pedido vai até o fim do vídeo")):
            teste.registrar(cod, desc, BLOQUEADO, "sem o vídeo do VER5 ou sem o pacote app-plates")
    else:
        # --- T31: STOP depois das primeiras detecções
        p = start(bus, "VER5", fonte_longa, "stop", ttl_seconds=300)
        bus.esperar(lambda: len(msgs(bus, p)) >= 5, ESPERA_PRIMEIRA_S)
        if len(msgs(bus, p)) < 5:
            teste.registrar("T31", "STOP interrompe a equipe ativa", FALHOU, "não chegaram 5 detecções para interromper")
        else:
            comando(bus, {"action": "STOP", "squad": "VER5"}, "VER5")
            t_stop = time.monotonic()
            lista = esperar_fim(bus, p)
            depois = [t for t, _ in lista if t > t_stop + 2]
            teste.registrar("T31", "STOP interrompe a equipe ativa", FALHOU if depois else PASSOU,
                            f"{len(lista)} mensagens; {len(depois)} chegaram mais de 2 s depois do STOP")
        esperados.append(("VER5", "stop", {"stopped_by_command"}))

        # --- T32: TTL curto sem HEARTBEAT (outra equipe, para não renovar o pedido anterior)
        p = start(bus, "VER6", fonte_longa, "ttl", ttl_seconds=TTL_CURTO_S)
        lista = esperar_fim(bus, p)
        if not lista:
            # O relógio do TTL começa antes de carregar a engine: se a carga passar do TTL, o pedido
            # expira antes do 1º quadro. O motivo (ttl_expired) é conferido no log (T40).
            teste.registrar("T32", "Sem HEARTBEAT, o pedido expira no TTL", AVISO,
                            f"nenhuma detecção: a carga da engine passou de {TTL_CURTO_S} s? (motivo no T40)")
        else:
            dur = lista[-1][0] - p["enviado"]
            teste.registrar("T32", "Sem HEARTBEAT, o pedido expira no TTL",
                            PASSOU if dur <= TTL_CURTO_S + 3 else FALHOU,
                            f"TTL {TTL_CURTO_S} s; última mensagem {dur:.1f} s após o START ({len(lista)} mensagens)")
        esperados.append(("VER6", "ttl", {"ttl_expired"}))

        # --- T33: mesmo TTL curto, mas com HEARTBEAT a cada 1,5 s
        p = start(bus, "VER3", fonte_longa, "heartbeat", ttl_seconds=TTL_CURTO_S)
        limite = time.monotonic() + ESPERA_PRIMEIRA_S
        ultima_msg = time.monotonic()
        visto = 0
        while time.monotonic() < limite:
            comando(bus, {"action": "HEARTBEAT", "squad": "VER3", "ttl_seconds": TTL_CURTO_S}, "VER3")
            bus.esperar(lambda: False, 1.5)
            n = len(msgs(bus, p))
            if n > visto:
                visto, ultima_msg = n, time.monotonic()
            elif visto and time.monotonic() - ultima_msg > SILENCIO_FIM_S:
                break
        lista = msgs(bus, p)
        if not lista:
            teste.registrar("T33", "Com HEARTBEAT, o pedido vai até o fim do vídeo", FALHOU, "nenhuma detecção")
        else:
            dur = lista[-1][0] - p["enviado"]
            teste.registrar("T33", "Com HEARTBEAT, o pedido vai até o fim do vídeo",
                            PASSOU if dur > TTL_CURTO_S + 1 else AVISO,
                            f"{len(lista)} mensagens em {dur:.1f} s (TTL {TTL_CURTO_S} s renovado)"
                            + ("" if dur > TTL_CURTO_S + 1 else "; o vídeo acabou antes do TTL, inconclusivo"))
        esperados.append(("VER3", "heartbeat", {"source_completed"}))

    # --- log do container i1 (passo externo)
    caminho = os.path.join(os.environ.get("RESULT_DIR", "/resultados"), ".i1-log.txt")
    log(f"PEDE_LOG — o i1.sh grava o log do container i1 em {caminho}")
    if not esperar_passo(bus, "log", espera_s=120) or not os.path.isfile(caminho):
        for cod in ("T02", "T30", "T40", "T41", "T42"):
            teste.registrar(cod, "Conferência pelo log do i1", BLOQUEADO, "o i1.sh não entregou o log")
        return teste.concluir(bus)
    with open(caminho, encoding="utf-8", errors="replace") as f:
        texto = f.read()

    ignorados = len(re.findall(r"Comando ignorado", texto))
    teste.registrar("T02", "Comandos inválidos ignorados sem derrubar o serviço",
                    PASSOU if ignorados >= 2 else FALHOU, f"{ignorados} 'Comando ignorado' no log (esperado 2)")

    encerradas = re.findall(r"Sessão '([^']+)' encerrada \(([^)]+)\) \| quadros publicados: (\d+)", texto)
    teste.extras["encerramentos_no_log"] = encerradas
    restantes = list(encerradas)
    divergencias = []
    erro_ok = False
    for squad, rotulo, aceitos in esperados:
        idx = next((i for i, (s, _, _) in enumerate(restantes) if s == squad), None)
        if idx is None:
            divergencias.append(f"{rotulo}: {squad} sem encerramento no log")
            continue
        _, motivo, _ = restantes.pop(idx)
        if motivo not in aceitos:
            divergencias.append(f"{rotulo}: {squad} encerrou com '{motivo}' (esperado {'/'.join(sorted(aceitos))})")
        elif rotulo == "erro":
            erro_ok = True
    teste.registrar("T30", "Vídeo inexistente vira erro registrado e o I1 segue atendendo",
                    PASSOU if erro_ok else FALHOU,
                    "pedido VER1 encerrado com 'error'" if erro_ok else "sem encerramento 'error' do VER1 no log")
    teste.registrar("T40", "Motivos de encerramento no log batem com os pedidos",
                    FALHOU if divergencias else PASSOU,
                    "; ".join(divergencias) if divergencias else
                    ", ".join(f"{s}:{m}" for s, m, _ in encerradas[-len(esperados):]))

    antes = re.search(r"^RESTARTS_ANTES=(\d+)", texto, re.M)
    depois = re.search(r"^RESTARTS_DEPOIS=(\d+)", texto, re.M)
    if antes and depois:
        n = int(depois.group(1)) - int(antes.group(1))
        teste.registrar("T41", "O serviço i1 não reiniciou durante o teste", PASSOU if n == 0 else FALHOU,
                        f"RestartCount {antes.group(1)} → {depois.group(1)}")
    else:
        teste.registrar("T41", "O serviço i1 não reiniciou durante o teste", BLOQUEADO, "RestartCount fora do log")

    oom = len(re.findall(r"OUT_OF_MEMORY|NvMap\w*.*error 12", texto))
    teste.registrar("T42", "Sem falta de memória da GPU no log", PASSOU if oom == 0 else AVISO,
                    f"{oom} linha(s) com OUT_OF_MEMORY/NvMap error 12" if oom else "nenhuma")
    return teste.concluir(bus)


if __name__ == "__main__":
    sys.exit(main())
