#!/usr/bin/env python3
"""Publica os 4 eventos de exemplo do I8 no Kafka da turma (P3 / SIS-1, build do A1).

Roda dentro da imagem do publisher do I8 (validacao-local/Dockerfile.publisher), com o
repositório do I8 em /repo. Faz o mesmo que a composição local do VER-1 (composicao-ver1/
provar.py, função prepare) para tornar os mocks publicáveis de novo: message_id, session_id,
sequence e horários novos. Depois chama o publicador oficial do I8 (scripts.publish_events),
que valida cada evento contra o contrato 2.0 e a taxonomia do A1 antes de publicar.

Não há inferência: o repositório do I8 não traz modelo treinado (README do I8, etapas 11-15).
São os eventos CONFORMING, NON_CONFORMING, ANOMALY e UNCERTAIN de shared/mocks/kafka-2.0.
"""

import json
import os
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, "/repo")
from scripts import publish_events  # noqa: E402  (código do I8, sem alteração)

MOCKS = Path("/repo/shared/mocks/kafka-2.0")
TAXONOMIA = Path(os.environ["I8_TAXONOMIA_DIR"])
VERSAO = os.environ["I8_TAXONOMIA_VERSAO"]


def instante(t):
    return t.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def main():
    arquivos = sorted(MOCKS.glob("i8-piece-*.json"))
    if not arquivos:
        raise SystemExit(f"nenhum mock em {MOCKS}")
    sessao = str(uuid.uuid4())
    agora = datetime.now(timezone.utc)
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8") as saida:
        for seq, arq in enumerate(arquivos):
            evento = json.loads(arq.read_text(encoding="utf-8"))
            evento.update(
                message_id=str(uuid.uuid4()),
                session_id=sessao,
                sequence=seq,
                artifact_version="p3-exemplos-i8",
                captured_at=instante(agora - timedelta(milliseconds=120)),
                occurred_at=instante(agora - timedelta(milliseconds=40)),
                published_at=instante(agora),
            )
            saida.write(json.dumps(evento, ensure_ascii=False) + "\n")
    print(f"[P3] {len(arquivos)} eventos de exemplo do I8, sessão {sessao}", file=sys.stderr, flush=True)
    publish_events.main([
        "--input", saida.name,
        "--taxonomy", str(TAXONOMIA / "content.json"),
        "--taxonomy-descriptor", str(TAXONOMIA / "descriptor.json"),
        "--taxonomy-version", VERSAO,
    ])


if __name__ == "__main__":
    main()
