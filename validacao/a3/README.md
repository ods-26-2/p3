# Validação do A3

Validação do A3 · Monitoramento / eventos (VER-6) no nível do sistema, na build `builds/a3/` do P3.
O contexto geral está em [`../README.md`](../README.md); o resultado e a análise, em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** scripts prontos; **ainda não executados na Jetson** (testados só fora da placa, sem os serviços reais).

## O que é o A3 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a3` | `ods-a3:<A3_REF>` | 8501 | painel Streamlit (broker forçado pelo contorno do P3) |
| `s3` | `ods-s3:<S3_REF>` | — | alertas (só comandos) |
| `i2, s1` | `ods-i2/ods-s1` | — | rastreio e zonas |
| `p4, i1 (sob demanda)` | `ods-p4/ods-i1` | — | vídeo e detecção |

Projeto Docker `ods-a3`. O código fica nos repositórios das equipes; a composição, em `builds/a3/`.

## As três verificações

| Nível | Comando | O que cobre |
|---|---|---|
| Sistema (S1–S9) | `../validacao-geral/validar-sistema.sh a3` | contêineres, memória, portas, volumes, reinício, imagens, disco, segredos, logs |
| Fluxo pela API (F) | `./validar-a3-fluxo.sh` | ver abaixo |
| Aceitação pelo Kafka (C) | `cd ../../builds/a3 && ./a3.sh testar` | a cadeia da aplicação no Kafka da turma, com o validador de contrato do B4 |

O fluxo pela API cobre:
- saúde do Streamlit e página.
- contorno do broker fixo presente no container.

## Como executar

```bash
cd /opt/ods/p3/builds && ./ods.sh trocar a3          # sobe a build (remove as outras)
cd /opt/ods/p3/validacao
./validacao-geral/validar-sistema.sh a3               # S1–S9 (acrescente --queda <serviço> para o teste de queda)
./a3/validar-a3-fluxo.sh                           # fluxo pela API
cd ../builds/a3 && ./a3.sh testar                  # aceitação; relatório em builds/a3/resultados/
```

Cada script grava a saída com data em `evidencias/` (o teste de aceitação grava em `builds/a3/resultados/`;
copie o `.txt` para `evidencias/` ao registrar a validação). Código de saída = número de falhas.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a3-fluxo.sh` | Fluxo pela API, com dados de teste removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios, resultado esperado, resultado obtido e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
