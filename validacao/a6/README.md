# Validação do A6

Validação do A6 · Libras / acessibilidade (APL-2) no nível do sistema, na build `builds/a6/` do P3.
O contexto geral está em [`../README.md`](../README.md); o resultado e a análise, em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** scripts prontos; **ainda não executados na Jetson** (testados só fora da placa, sem os serviços reais).

## O que é o A6 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a6` | `ods-a6:<A6_REF>` | 8086 | tradutor (--no-mock) |
| `s6` | `ods-s6:<I4_REF>` | — | síntese de Libras (do repo i4) |
| `i4-amostra (sob demanda)` | `ods-s6:<I4_REF>` | — | publicador de amostra do I4 |

Projeto Docker `ods-a6`. O código fica nos repositórios das equipes; a composição, em `builds/a6/`.

## As três verificações

| Nível | Comando | O que cobre |
|---|---|---|
| Sistema (S1–S9) | `../validacao-geral/validar-sistema.sh a6` | contêineres, memória, portas, volumes, reinício, imagens, disco, segredos, logs |
| Fluxo pela API (F) | `./validar-a6-fluxo.sh` | ver abaixo |
| Aceitação pelo Kafka (C) | `cd ../../builds/a6 && ./a6.sh testar` | a cadeia da aplicação no Kafka da turma, com o validador de contrato do B4 |

O fluxo pela API cobre:
- página e estado (Kafka, léxico).
- tradução português -> Libras.
- 404 de rota inexistente.
- trajetória do S6 na pasta compartilhada.

## Como executar

```bash
cd /opt/ods/p3/builds && ./ods.sh trocar a6          # sobe a build (remove as outras)
cd /opt/ods/p3/validacao
./validacao-geral/validar-sistema.sh a6               # S1–S9 (acrescente --queda <serviço> para o teste de queda)
./a6/validar-a6-fluxo.sh                           # fluxo pela API
cd ../builds/a6 && ./a6.sh testar                  # aceitação; relatório em builds/a6/resultados/
```

Cada script grava a saída com data em `evidencias/` (o teste de aceitação grava em `builds/a6/resultados/`;
copie o `.txt` para `evidencias/` ao registrar a validação). Código de saída = número de falhas.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a6-fluxo.sh` | Fluxo pela API, com dados de teste removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios, resultado esperado, resultado obtido e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
