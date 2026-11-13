# Validação do A1

Validação do A1 · Indústria / inspeção (VER-1) no nível do sistema, na build `builds/a1/` do P3.
O contexto geral está em [`../README.md`](../README.md); o resultado e a análise, em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** scripts prontos; **ainda não executados na Jetson** (testados só fora da placa, sem os serviços reais).

## O que é o A1 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a1-backend` | `ods-a1-backend:<A1_REF>` | 127.0.0.1:8010 | API v1 (FastAPI); consome ods.industria.defeito_classificado |
| `a1-frontend` | `ods-a1-frontend:<A1_REF>` | 5500 | interface (nginx, repassa /api/ ao backend) |
| `a1-db` | `postgres:17-alpine` | não publicada | banco do A1 |
| `s4` | `ods-s4:<S4_REF>` | 127.0.0.1:18084 | evidência de mídia |
| `i8 (sob demanda)` | `ods-i8-publisher:<I8_REF>` | — | publisher real do I8 com os eventos de exemplo |

Projeto Docker `ods-a1`. O código fica nos repositórios das equipes; a composição, em `builds/a1/`.

## As três verificações

| Nível | Comando | O que cobre |
|---|---|---|
| Sistema (S1–S9) | `../validacao-geral/validar-sistema.sh a1` | contêineres, memória, portas, volumes, reinício, imagens, disco, segredos, logs |
| Fluxo pela API (F) | `./validar-a1-fluxo.sh` | ver abaixo |
| Aceitação pelo Kafka (C) | `cd ../../builds/a1 && ./a1.sh testar` | a cadeia da aplicação no Kafka da turma, com o validador de contrato do B4 |

O fluxo pela API cobre:
- saúde ONLINE com banco, consumidor Kafka e S4.
- consultas de inspeção, fila de revisão e 404 de inexistente.
- detalhe e histórico de uma inspeção (se houver).
- interface e API pelo proxy do nginx.

## Como executar

```bash
cd /opt/ods/p3/builds && ./ods.sh trocar a1          # sobe a build (remove as outras)
cd /opt/ods/p3/validacao
./validacao-geral/validar-sistema.sh a1               # S1–S9 (acrescente --queda <serviço> para o teste de queda)
./a1/validar-a1-fluxo.sh                           # fluxo pela API
cd ../builds/a1 && ./a1.sh testar                  # aceitação; relatório em builds/a1/resultados/
```

Cada script grava a saída com data em `evidencias/` (o teste de aceitação grava em `builds/a1/resultados/`;
copie o `.txt` para `evidencias/` ao registrar a validação). Código de saída = número de falhas.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a1-fluxo.sh` | Fluxo pela API, com dados de teste removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios, resultado esperado, resultado obtido e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
