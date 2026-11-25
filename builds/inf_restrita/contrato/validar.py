"""validar.py — confere mensagens do Kafka contra o schema do repositório que as produziu (P3).

Roda DENTRO da imagem do produtor (ods-i1-gpu, ods-i2, ods-i3), que já traz o jsonschema e a
pasta schemas/ do próprio repositório. Uso (o inf_restrita.sh monta os arquivos):

    python validar.py <schema.json> <mensagens.jsonl> [source_id]

Uma mensagem JSON por linha (saída do kafka-console-consumer). Com source_id, só conta as
mensagens desse source_id (o Kafka da placa é compartilhado: outras builds publicam nos mesmos
tópicos). Imprime uma linha de resumo "CONTRATO <válidas> <total> <primeiro erro>", outra com as artifact_version vistas
("VERSOES a,b") e termina com 0
se todas as contadas são válidas e há ao menos uma.
"""
import json
import sys

from jsonschema import validators


def main() -> int:
    schema_arq, msgs_arq = sys.argv[1], sys.argv[2]
    filtro = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] not in ("", "-") else None
    with open(schema_arq, encoding="utf-8") as f:
        schema = json.load(f)
    cls = validators.validator_for(schema)
    cls.check_schema(schema)
    validador = cls(schema)
    total = validas = 0
    primeiro = ""
    versoes = set()
    with open(msgs_arq, encoding="utf-8", errors="replace") as f:
        for n, linha in enumerate(f, 1):
            linha = linha.strip()
            if not linha.startswith("{"):
                continue
            try:
                msg = json.loads(linha)
            except ValueError as exc:
                total += 1
                primeiro = primeiro or f"linha {n}: JSON inválido ({exc})"
                continue
            if filtro and not (isinstance(msg, dict) and msg.get("source_id") == filtro):
                continue
            total += 1
            if isinstance(msg, dict) and msg.get("artifact_version"):
                versoes.add(str(msg["artifact_version"]))
            erros = sorted(validador.iter_errors(msg), key=lambda e: list(e.absolute_path))
            if erros:
                e = erros[0]
                caminho = "/".join(str(p) for p in e.absolute_path) or "(raiz)"
                primeiro = primeiro or f"linha {n}: {caminho}: {e.message[:160]}"
            else:
                validas += 1
    print(f"CONTRATO {validas} {total} {primeiro or '-'}")
    print(f"VERSOES {','.join(sorted(versoes)) or '-'}")
    return 0 if total and validas == total else 1


if __name__ == "__main__":
    sys.exit(main())
