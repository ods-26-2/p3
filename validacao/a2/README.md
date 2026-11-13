# Validação do A2

Validação do A2 · Acesso / identificação (VER-2) no nível do sistema, na build `builds/a2/` do P3.
O contexto geral está em [`../README.md`](../README.md); o resultado e a análise, em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** scripts prontos; **ainda não executados na Jetson** (testados só fora da placa, sem os serviços reais).

## O que é o A2 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a2` | `ods-a2:<A2_REF>` | 8000, 8001 | liberação de catraca (simulada) + API de registros |
| `a2-cracha` | `ods-a2-cracha:<A2_REF>` | 8082 | gerador de crachás (web-app) |
| `i6` | `ods-i6:<I6_REF>` | — | leitor de QR (câmera IP ou arquivo) |
| `s4` | `ods-s4:<S4_REF>` | 127.0.0.1:18084 | snapshot da entrada |

Projeto Docker `ods-a2`. O código fica nos repositórios das equipes; a composição, em `builds/a2/`.

## As três verificações

| Nível | Comando | O que cobre |
|---|---|---|
| Sistema (S1–S9) | `../validacao-geral/validar-sistema.sh a2` | contêineres, memória, portas, volumes, reinício, imagens, disco, segredos, logs |
| Fluxo pela API (F) | `./validar-a2-fluxo.sh` | ver abaixo |
| Aceitação pelo Kafka (C) | `cd ../../builds/a2 && ./a2.sh testar` | a cadeia da aplicação no Kafka da turma, com o validador de contrato do B4 |

O fluxo pela API cobre:
- saúde e registros de acesso.
- validação de filtro (400) e 404 de inexistente.
- página de visualização.
- gerador de crachás.

## Como executar

```bash
cd /opt/ods/p3/builds && ./ods.sh trocar a2          # sobe a build (remove as outras)
cd /opt/ods/p3/validacao
./validacao-geral/validar-sistema.sh a2               # S1–S9 (acrescente --queda <serviço> para o teste de queda)
./a2/validar-a2-fluxo.sh                           # fluxo pela API
cd ../builds/a2 && ./a2.sh testar                  # aceitação; relatório em builds/a2/resultados/
```

Cada script grava a saída com data em `evidencias/` (o teste de aceitação grava em `builds/a2/resultados/`;
copie o `.txt` para `evidencias/` ao registrar a validação). Código de saída = número de falhas.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a2-fluxo.sh` | Fluxo pela API, com dados de teste removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios, resultado esperado, resultado obtido e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
