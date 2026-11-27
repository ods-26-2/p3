"""validar_a1.py — confere eventos do I8 com o validador do CONSUMIDOR, o próprio A1 (P3).

Roda DENTRO da imagem do publicador do I8 (python 3.11 com jsonschema), com o clone do A1 em /a1:
carrega /a1/backend/contracts.py pelo caminho (sem importar o pacote backend inteiro) e chama
validate_piece_analysis, que usa os schemas do próprio A1 (shared/schemas/6c). Uso (o inf_a1.sh monta):

    python validar_a1.py <mensagens.jsonl> [artifact_version]

Com artifact_version, só conta os eventos dela (o Kafka da nuvem é compartilhado). Imprime:
    CONTRATO <válidas> <total> <primeiro erro>
    CONTRATOS <schema/versão vistos>
"""
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("a1_contracts", "/a1/backend/contracts.py")
contratos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contratos)


def main() -> int:
    arq = sys.argv[1]
    filtro = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] not in ("", "-") else None
    total = validas = 0
    primeiro = ""
    vistos = set()
    with open(arq, encoding="utf-8", errors="replace") as f:
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
            if filtro and not (isinstance(msg, dict) and msg.get("artifact_version") == filtro):
                continue
            total += 1
            vistos.add(f"{msg.get('schema')}/{msg.get('schema_version')}")
            try:
                contratos.validate_piece_analysis(msg)
            except Exception as exc:  # noqa: BLE001 — ContractValidationError e afins
                primeiro = primeiro or f"linha {n}: {str(exc)[:160]}"
            else:
                validas += 1
    print(f"CONTRATO {validas} {total} {primeiro or '-'}")
    print(f"CONTRATOS {','.join(sorted(vistos)) or '-'}")
    return 0 if total and validas == total else 1


if __name__ == "__main__":
    sys.exit(main())
