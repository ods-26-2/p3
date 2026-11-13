# Relatório de validação do A2 · Acesso / identificação

**Situação:** não executado na Jetson. Preencha a coluna "Obtido" com a execução na placa e
copie as saídas para `evidencias/`.

| Item | Valor |
|---|---|
| Build | `builds/a2/` (commits em `a2.env`) |
| Data da execução | — |
| Placa | Jetson Orin `ods-pc`, JetPack 6.2.1 |
| Kafka | da turma, `172.18.4.56:9093` |

## Critérios de sistema (`validar-sistema.sh a2`)

| ID | Critério | Obtido |
|---|---|---|
| S1 | Contêineres estáveis e saudáveis | — |
| S2 | Memória (2.500 MB/serviço, 5.150 MB total) | — |
| S3 | Só as portas da build; internas em 127.0.0.1 | — |
| S4 | Dados em volumes | — |
| S5 | Reinício automático (e teste de queda) | — |
| S6 | Imagens com versão (sem latest) | — |
| S7 | Disco ≥ 4 GB livres | — |
| S8 | Segredos fora do Git e das imagens | — |
| S9 | Logs sem erros recorrentes | — |

## Fluxo pela API (`validar-a2-fluxo.sh`)

| ID | Verificação | Obtido |
|---|---|---|
| F1 | saúde e registros de acesso | — |
| F2 | validação de filtro (400) e 404 de inexistente | — |
| F3 | página de visualização | — |
| F4 | gerador de crachás | — |

## Aceitação pelo Kafka (`a2.sh testar`)

"Esperado" é o resultado previsto com o código fixado no `a2.env` (13/11/2026). BLOQUEADO e AVISO
não reprovam; "(entrada simulada: X)" quer dizer que o teste publica a mensagem que X publicaria,
porque X ainda não existe no Kafka.

| Item | Verificação | Esperado | Obtido | Observação |
|---|---|---|---|---|
| C01 | API de registros | PASSOU | — |  |
| C02 | Leituras reais do I6 | AVISO | — | só passa com QR na fonte do I6 |
| C03 | Crachá válido registrado (I6 simulado) | PASSOU | — |  |
| C04 | Crachá vencido negado | PASSOU | — |  |
| C05 | Snapshot pedido ao S4 | PASSOU | — |  |
| C06 | Snapshot entregue | PASSOU | — |  |
| C07 | Mídia no registro | PASSOU | — |  |
| C08 | I6 lendo o P4 | BLOQUEADO | — | formato de socket diferente |
| C09 | Envelope 1.0 | a confirmar | — |  |

## Conclusão

— (preencher depois da execução na Jetson)

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
