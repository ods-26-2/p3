"""validar_i6.py — confere mensagens de ods.i6.code_read com o validador do próprio I6 (P3).

Roda DENTRO da imagem do I6 (ods-i6), com o validar_evento_i6 de /app/leitor.py (o contrato que o I6
aplica antes de publicar). Importar o leitor.py não o põe para rodar (main() só no __main__).
Uso (o inf_a2.sh monta):

    python validar_i6.py <mensagens.jsonl> [source_id] [idade_max_s]

Com source_id, só conta as mensagens dele (o Kafka da nuvem é compartilhado). Imprime:
    CONTRATO <válidas> <total> <primeiro erro>
    IDADE <maior atraso, em s, entre captured_at e published_at> <quantas passam de idade_max_s>
    CODIGOS <decoded_data distintos, separados por vírgula>
"""
import json
import sys
from datetime import datetime

sys.path.insert(0, "/app")
from leitor import validar_evento_i6  # noqa: E402


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
    codigos = []
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
            dado = (msg.get("payload") or {}).get("decoded_data")
            if dado and dado not in codigos:
                codigos.append(str(dado))
            cap, pub = instante(msg.get("captured_at")), instante(msg.get("published_at"))
            if cap and pub:
                idade = (pub - cap).total_seconds()
                idade_pior = max(idade_pior, idade)
                if idade_max and idade > idade_max:
                    velhas += 1
            try:
                validar_evento_i6(msg)
            except Exception as exc:  # noqa: BLE001 — o validador do I6 levanta ValueError/TypeError
                primeiro = primeiro or f"linha {n}: {str(exc)[:160]}"
            else:
                validas += 1
    print(f"CONTRATO {validas} {total} {primeiro or '-'}")
    print(f"IDADE {idade_pior:.1f} {velhas}")
    print(f"CODIGOS {','.join(codigos) or '-'}")
    return 0 if total and validas == total else 1


if __name__ == "__main__":
    sys.exit(main())
