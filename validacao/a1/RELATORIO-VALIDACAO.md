# Relatório de validação do A1 · Indústria / inspeção

**Situação:** não executado na Jetson. Preencha a coluna "Obtido" com a execução na placa e
copie as saídas para `evidencias/`.

| Item | Valor |
|---|---|
| Build | `builds/a1/` (commits em `a1.env`) |
| Data da execução | — |
| Placa | Jetson Orin `ods-pc`, JetPack 6.2.1 |
| Kafka | da turma, `172.18.4.56:9093` |

## Critérios de sistema (`validar-sistema.sh a1`)

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

## Fluxo pela API (`validar-a1-fluxo.sh`)

| ID | Verificação | Obtido |
|---|---|---|
| F1 | saúde ONLINE com banco, consumidor Kafka e S4 | — |
| F2 | consultas de inspeção, fila de revisão e 404 de inexistente | — |
| F3 | detalhe e histórico de uma inspeção (se houver) | — |
| F4 | interface e API pelo proxy do nginx | — |

## Aceitação pelo Kafka (`a1.sh testar`)

"Esperado" é o resultado previsto com o código fixado no `a1.env` (13/11/2026). BLOQUEADO e AVISO
não reprovam; "(entrada simulada: X)" quer dizer que o teste publica a mensagem que X publicaria,
porque X ainda não existe no Kafka.

| Item | Verificação | Esperado | Obtido | Observação |
|---|---|---|---|---|
| C01 | Eventos do I8 no Kafka | PASSOU | — |  |
| C02 | Inspeções registradas pelo A1 (API) | PASSOU | — |  |
| C03 | Pedidos de evidência do A1 ao S4 | PASSOU | — |  |
| C04 | Respostas do S4 | PASSOU | — | o S4 precisa do vídeo linha1.mp4 no buffer |
| C05 | Clipes do S4 para o A1 | PASSOU | — |  |
| C06 | Evidência AVAILABLE na inspeção | PASSOU | — |  |
| C07 | Tópico da 6c | AVISO | — | A1/I8 usam ods.industria.defeito_classificado |
| C08 | Triagem pelo P7 | BLOQUEADO | — | P7 sem Kafka |
| C09 | Inferência real do I8 | BLOQUEADO | — | sem modelo treinado |
| C10 | Envelope 1.0 (validador do B4) | a confirmar | — |  |

## Conclusão

— (preencher depois da execução na Jetson)

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
