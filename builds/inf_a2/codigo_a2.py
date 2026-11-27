#!/usr/bin/env python3
"""codigo_a2.py — P3 / SIS-1: monta e confere o código de QR que o A2 aceita, sem o código da VER-2.

Formato lido em A2Local/LiberacaoCatraca/interpreta_codigo.py e regras_entrada.py (a2 72cedda):
  texto do QR = 32 caracteres hex = AES-256-ECB(chave A2_AES_KEY, 32 bytes ASCII) de 16 bytes:
    bytes 0..3   cpf_base (9 primeiros dígitos do CPF, inteiro big-endian; o A2 calcula o DV)
    bytes 4..7   start_timestamp (epoch, big-endian)
    bytes 8..11  end_timestamp
    byte  12     day_mask (7 bits; o A2 ainda não usa)
    bytes 13..15 zero
  o A2 libera se start_timestamp <= agora <= end_timestamp e o CPF tiver 11 dígitos.

A cifra é feita pelo openssl da placa (só biblioteca padrão aqui). A chave vem da variável
A2_AES_KEY (o inf_a2.sh a lê do inf_a2.secrets.env), nunca dos argumentos:

  A2_AES_KEY=… python3 codigo_a2.py gerar <cpf_base> <início_epoch> <fim_epoch>   → imprime o hex
  A2_AES_KEY=… python3 codigo_a2.py conferir <hex> [agora_epoch]                 → "OK cpf fim" ou "ERRO motivo"
"""
import os
import subprocess
import sys
import time


def _aes(chave: str, dados: bytes, decifrar: bool) -> bytes:
    k = chave.encode("ascii")
    if len(k) != 32:
        raise ValueError("A2_AES_KEY deve ter exatamente 32 caracteres ASCII")
    cmd = ["openssl", "enc", "-aes-256-ecb", "-nopad", "-K", k.hex()] + (["-d"] if decifrar else [])
    r = subprocess.run(cmd, input=dados, capture_output=True, check=False)
    if r.returncode != 0 or len(r.stdout) != 16:
        raise RuntimeError(f"openssl falhou: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


def dv_cpf(base: int) -> str:
    d = [int(c) for c in str(base).zfill(9)]
    r1 = sum(x * w for x, w in zip(d, range(10, 1, -1))) % 11
    dv1 = 0 if r1 < 2 else 11 - r1
    r2 = sum(x * w for x, w in zip(d + [dv1], range(11, 1, -1))) % 11
    dv2 = 0 if r2 < 2 else 11 - r2
    return f"{dv1}{dv2}"


def gerar(chave: str, cpf_base: int, inicio: int, fim: int) -> str:
    if not 0 <= cpf_base <= 999_999_999:
        raise ValueError("cpf_base deve ter até 9 dígitos")
    if inicio > fim:
        raise ValueError("início depois do fim")
    bloco = (cpf_base.to_bytes(4, "big") + inicio.to_bytes(4, "big") + fim.to_bytes(4, "big")
             + bytes([0x7F]) + bytes(3))
    return _aes(chave, bloco, False).hex()


def conferir(chave: str, texto: str, agora: int) -> str:
    try:
        bruto = _aes(chave, bytes.fromhex(texto.strip()), True)
    except (ValueError, RuntimeError) as exc:
        return f"ERRO não decifra: {exc}"
    base = int.from_bytes(bruto[0:4], "big")
    ini = int.from_bytes(bruto[4:8], "big")
    fim = int.from_bytes(bruto[8:12], "big")
    if base > 999_999_999:
        return "ERRO cpf_base inválido (chave errada?)"
    if ini > fim:
        return "ERRO início depois do fim (chave errada?)"
    cpf = str(base).zfill(9) + dv_cpf(base)
    if not ini <= agora <= fim:
        return f"ERRO fora da validade ({ini}..{fim}, agora {agora}) cpf {cpf}"
    return f"OK {cpf} {fim}"


def main() -> int:
    chave = os.environ.get("A2_AES_KEY", "")
    if not chave:
        print("defina A2_AES_KEY", file=sys.stderr)
        return 2
    if len(sys.argv) >= 5 and sys.argv[1] == "gerar":
        print(gerar(chave, int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])))
        return 0
    if len(sys.argv) >= 3 and sys.argv[1] == "conferir":
        agora = int(sys.argv[3]) if len(sys.argv) > 3 else int(time.time())
        saida = conferir(chave, sys.argv[2], agora)
        print(saida)
        return 0 if saida.startswith("OK") else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
