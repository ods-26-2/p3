# Validação do A4

Validação do A4 · Esporte / arbitragem (INV-1) no nível do sistema, na build `builds/a4/` do P3.
O contexto geral está em [`../README.md`](../README.md); o resultado e a análise, em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** scripts prontos; **ainda não executados na Jetson** (testados só fora da placa, sem os serviços reais).

## O que é o A4 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a4-back` | `ods-a4-back:<A4_REF>` | 8000 | API do árbitro |
| `a4-front` | `ods-a4-front:<A4_REF>` | 3000 | interface (Next.js) |
| `i2, s1` | `ods-i2/ods-s1` | — | rastreio e posição |
| `s4` | `ods-s4:<S4_REF>` | 18084 (aberta) | replay no navegador |
| `p4, i1, i3 (sob demanda)` | `ods-p4/ods-i1/ods-i3` | — | vídeo, bola (app-volei) e calibração |

Projeto Docker `ods-a4`. O código fica nos repositórios das equipes; a composição, em `builds/a4/`.

## As três verificações

| Nível | Comando | O que cobre |
|---|---|---|
| Sistema (S1–S9) | `../validacao-geral/validar-sistema.sh a4` | contêineres, memória, portas, volumes, reinício, imagens, disco, segredos, logs |
| Fluxo pela API (F) | `./validar-a4-fluxo.sh` | ver abaixo |
| Aceitação pelo Kafka (C) | `cd ../../builds/a4 && ./a4.sh testar` | a cadeia da aplicação no Kafka da turma, com o validador de contrato do B4 |

O fluxo pela API cobre:
- saúde: Kafka ligado, sem modo demo, token exigido.
- 401 sem token e com token errado; 422 de ângulo fora da faixa.
- 404 de partida inexistente; estado da câmera e do player.
- interface.

## Como executar

```bash
cd /opt/ods/p3/builds && ./ods.sh trocar a4          # sobe a build (remove as outras)
cd /opt/ods/p3/validacao
./validacao-geral/validar-sistema.sh a4               # S1–S9 (acrescente --queda <serviço> para o teste de queda)
./a4/validar-a4-fluxo.sh                           # fluxo pela API
cd ../builds/a4 && ./a4.sh testar                  # aceitação; relatório em builds/a4/resultados/
```

Cada script grava a saída com data em `evidencias/` (o teste de aceitação grava em `builds/a4/resultados/`;
copie o `.txt` para `evidencias/` ao registrar a validação). Código de saída = número de falhas.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a4-fluxo.sh` | Fluxo pela API, com dados de teste removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios, resultado esperado, resultado obtido e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
