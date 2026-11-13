# Validação do A5

Validação do A5 · EPI / segurança (VER-3) no nível do sistema, na build `builds/a5/` do P3.
O contexto geral está em [`../README.md`](../README.md); o resultado e a análise, em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** scripts prontos; **ainda não executados na Jetson** (testados só fora da placa, sem os serviços reais).

## O que é o A5 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a5-backend` | `ods-a5-backend:<A5_REF>` | 127.0.0.1:8000 | API (acesso pelo nginx) |
| `a5-frontend` | `ods-a5-frontend:<A5_REF>` | 8095 | interface e /registro |
| `s3` | `ods-s3:<S3_REF>` | — | alertas com ROUTING do A5 |
| `s4` | `ods-s4:<S4_REF>` | 127.0.0.1:18084 | evidência |
| `i9, i2, s1 (cadeia)` | `ods-i9/ods-i2/ods-s1` | — | EPI relacional, rastreio, zonas |

Projeto Docker `ods-a5`. O código fica nos repositórios das equipes; a composição, em `builds/a5/`.

## As três verificações

| Nível | Comando | O que cobre |
|---|---|---|
| Sistema (S1–S9) | `../validacao-geral/validar-sistema.sh a5` | contêineres, memória, portas, volumes, reinício, imagens, disco, segredos, logs |
| Fluxo pela API (F) | `./validar-a5-fluxo.sh` | ver abaixo |
| Aceitação pelo Kafka (C) | `cd ../../builds/a5 && ./a5.sh testar` | a cadeia da aplicação no Kafka da turma, com o validador de contrato do B4 |

O fluxo pela API cobre:
- interface e saúde pelo nginx.
- 401 com senha errada e sem login.
- login, sessão, alertas, catálogo, zonas e logout.

## Como executar

```bash
cd /opt/ods/p3/builds && ./ods.sh trocar a5          # sobe a build (remove as outras)
cd /opt/ods/p3/validacao
./validacao-geral/validar-sistema.sh a5               # S1–S9 (acrescente --queda <serviço> para o teste de queda)
./a5/validar-a5-fluxo.sh                           # fluxo pela API
cd ../builds/a5 && ./a5.sh testar                  # aceitação; relatório em builds/a5/resultados/
```

Cada script grava a saída com data em `evidencias/` (o teste de aceitação grava em `builds/a5/resultados/`;
copie o `.txt` para `evidencias/` ao registrar a validação). Código de saída = número de falhas.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a5-fluxo.sh` | Fluxo pela API, com dados de teste removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios, resultado esperado, resultado obtido e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
