# Imagem Base — ODS

## Informações do arquivo

| Item | Valor |
|---|---|
| Arquivo | `imagem-base-v1.tar.zst` |
| Tamanho compactado | 9.718.012.518 bytes (~9,1 GiB) |
| Tamanho descompactado | 23.357.327.360 bytes (~21,8 GiB) |
| SHA-256 | `21ecc4ada2912ee077589be450707e0b5bfdbab5d36f6462f7907344d2363ea7` |
| Gerada em | 30/10/2026, das 14:00 às 14:17 (-03) |
| Origem | `ods-pc` |
| L4T | R36.4.7 |
| JetPack | 6.2.1 |
| CUDA | 12.6 |
| Método de geração | Método B — tar da raiz `/` via SSH, compactado com zstd |
| Script | `gerar-imagem.sh` |

## Conteúdo do diretório

| Arquivo | Descrição |
|---|---|
| `imagem-base-v1.tar.zst` | Imagem base compactada |
| `imagem-base-v1.sha256` | Hash SHA-256 para verificação de integridade |
| `gerar-imagem.sh` | Script utilizado para gerar a imagem |
| `manifesto.txt` | Manifesto dos arquivos incluídos |
| `pacotes-instalados.txt` | Relação dos pacotes instalados no sistema de origem |
| `pacotes-travados.txt` | Relação dos pacotes com versões travadas |

## Exclusões

A imagem não inclui:

- `/home`
- `/tmp`
- `/var/tmp`
- Partições de boot e firmware
- Imagens Docker (não havia nenhuma no momento da geração)

## Verificação de integridade

Para verificar se o arquivo compactado corresponde ao hash SHA-256 registrado, execute:

```bash
sha256sum -c imagem-base-v1.sha256
```

O resultado esperado é:

```text
imagem-base-v1.tar.zst: OK
```

## Observações

Esta imagem representa uma cópia do sistema de arquivos raiz do equipamento de origem( por enquanto não disponibilizada devido seu tamanho), gerada via SSH e compactada utilizando zstd.

O arquivo foi produzido para servir como imagem base do ambiente ODS, preservando o estado do sistema e as informações necessárias para sua identificação e reprodução.
