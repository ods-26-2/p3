# Padrão de nomes e versionamento de imagens

## Formato
    ods/<serviço>:<versão>-jp6.2.1-b<ID>
Exemplo: `ods/base-gpu:0.1.0-jp6.2.1-b001`

| Campo | Regra |
|---|---|
| `<serviço>` | minúsculas e hífen (`base-gpu`, `monitor`, `p2-runtime`) |
| `<versão>` | SemVer do serviço (X.Y.Z) |
| `jp6.2.1` | JetPack alvo |
| `b<ID>` | nº sequencial de build, 3 dígitos, gerado pelo `gerar-imagem.sh` |

## Regras
1. **Proibido `:latest`** e qualquer tag sem versão.
2. **Tag nunca reaproveitada.** Mudou algo, muda o `b<ID>`. Nunca recriar uma tag existente.
3. **Labels obrigatórios em todo build:** `ods.servico`, `ods.versao`, `ods.build`,
   `ods.jetpack`, `ods.l4t`, `ods.commit` (informado manualmente; `nao-informado` se omitido),
   `ods.fonte` (hash dos arquivos do build, automático), `ods.data` (UTC), `ods.base` (base usada).
4. **Base fixada por digest** (`FROM imagem@sha256:...`), nunca só por tag. Exceção: base própria `ods/...-bNNN` (tag nunca reaproveitada).
5. **Guardar a tag anterior:** manter as 2 últimas tags de cada serviço.
   Proibido `docker image prune -a`; a limpeza é feita só pelo script.
6. **Compose e deploy usam a tag completa**, lida do `.env`
   (`<SERVICO>_TAG` e `<SERVICO>_TAG_ANTERIOR`). Rollback = trocar para a anterior e subir.
7. **GPU:** o runtime padrão do Docker é `runc`. Todo serviço com GPU deve declarar
   `runtime: nvidia`, senão sobe sem GPU e sem erro.

## Cota
Total das imagens dentro de ~7 GB. Medir com `sudo docker system df -v`,
pois as camadas compartilhadas da base contam uma vez só.
