# Validação do A7

Validação do A7 · Restaurante / áudio e voz (VER-4) no nível do sistema, na build `builds/a7/` do P3.
O contexto geral está em [`../README.md`](../README.md); o resultado e a análise, em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** scripts prontos; **ainda não executados na Jetson** (testados só fora da placa, sem os serviços reais).

## O que é o A7 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a7` | `ods-a7:<A7_REF>` | 8000 | servidor do A7 (telas e API) |
| `i5 (sob demanda)` | `ods-i5:<I5_REF>` | — | transcrição de um áudio (Whisper em CPU) |

Projeto Docker `ods-a7`. O código fica nos repositórios das equipes; a composição, em `builds/a7/`.

## As três verificações

| Nível | Comando | O que cobre |
|---|---|---|
| Sistema (S1–S9) | `../validacao-geral/validar-sistema.sh a7` | contêineres, memória, portas, volumes, reinício, imagens, disco, segredos, logs |
| Fluxo pela API (F) | `./validar-a7-fluxo.sh` | ver abaixo |
| Aceitação pelo Kafka (C) | `cd ../../builds/a7 && ./a7.sh testar` | a cadeia da aplicação no Kafka da turma, com o validador de contrato do B4 |

O fluxo pela API cobre:
- saúde e cardápio.
- pedido por voz (texto) -> sessão e carrinho.
- sessão de teste apagada e conferida (404).

## Como executar

```bash
cd /opt/ods/p3/builds && ./ods.sh trocar a7          # sobe a build (remove as outras)
cd /opt/ods/p3/validacao
./validacao-geral/validar-sistema.sh a7               # S1–S9 (acrescente --queda <serviço> para o teste de queda)
./a7/validar-a7-fluxo.sh                           # fluxo pela API
cd ../builds/a7 && ./a7.sh testar                  # aceitação; relatório em builds/a7/resultados/
```

Cada script grava a saída com data em `evidencias/` (o teste de aceitação grava em `builds/a7/resultados/`;
copie o `.txt` para `evidencias/` ao registrar a validação). Código de saída = número de falhas.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a7-fluxo.sh` | Fluxo pela API, com dados de teste removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios, resultado esperado, resultado obtido e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
