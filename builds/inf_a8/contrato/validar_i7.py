"""validar_i7.py — confere mensagens de ods.i7.plate_read com o validador do próprio I7 (P3).

Roda DENTRO da imagem do I7 (ods-i7-gpu), com o validar_evento de scripts/publicador_eventos.py
(o contrato que o I7 aplica antes de publicar; só biblioteca padrão). Uso (o inf_a8.sh monta):

    python3 validar_i7.py <mensagens.jsonl> [source_id] [idade_max_s]

Uma mensagem JSON por linha (saída do kafka-console-consumer). Com source_id, só conta as
mensagens dele (o Kafka da nuvem é compartilhado). Imprime:
    CONTRATO <válidas> <total> <primeiro erro>
    VERSOES <artifact_version vistas>
    IDADE <idade máxima, em s, entre captured_at e published_at> <quantas passam de idade_max_s>
    PLACAS <placas lidas, separadas por vírgula>
"""
import json
import sys
from datetime import datetime

sys.path.insert(0, "/app/scripts")
from publicador_eventos import validar_evento  # noqa: E402


def instante(texto):
    try:
        return datetime.fromisoformat(str(texto).replace("Z", "+00:00"))
    except ValueError:
        return None


def main() -> int:
    arq = sys.argv[1]
    filtro = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] not in ("", "-") else None
    idade_max = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    total = validas = velhas = 0
    idade_pior = 0.0
    primeiro = ""
    versoes, placas = set(), []
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
            if filtro and not (isinstance(msg, dict) and msg.get("source_id") == filtro):
                continue
            total += 1
            if msg.get("artifact_version"):
                versoes.add(str(msg["artifact_version"]))
            placa = (msg.get("payload") or {}).get("license_plate")
            if placa:
                placas.append(str(placa))
            cap, pub = instante(msg.get("captured_at")), instante(msg.get("published_at"))
            if cap and pub:
                idade = (pub - cap).total_seconds()
                idade_pior = max(idade_pior, idade)
                if idade_max and idade > idade_max:
                    velhas += 1
            erros = validar_evento(msg)
            if erros:
                primeiro = primeiro or f"linha {n}: {erros[0][:160]}"
            else:
                validas += 1
    print(f"CONTRATO {validas} {total} {primeiro or '-'}")
    print(f"VERSOES {','.join(sorted(versoes)) or '-'}")
    print(f"IDADE {idade_pior:.1f} {velhas}")
    print(f"PLACAS {','.join(placas) or '-'}")
    return 0 if total and validas == total else 1


if __name__ == "__main__":
    sys.exit(main())
