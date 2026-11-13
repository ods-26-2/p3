# Relatório de validação do A7 · Restaurante / áudio e voz

**Situação:** não executado na Jetson. Preencha a coluna "Obtido" com a execução na placa e
copie as saídas para `evidencias/`.

| Item | Valor |
|---|---|
| Build | `builds/a7/` (commits em `a7.env`) |
| Data da execução | — |
| Placa | Jetson Orin `ods-pc`, JetPack 6.2.1 |
| Kafka | da turma, `172.18.4.56:9093` |

## Critérios de sistema (`validar-sistema.sh a7`)

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

## Fluxo pela API (`validar-a7-fluxo.sh`)

| ID | Verificação | Obtido |
|---|---|---|
| F1 | saúde e cardápio | — |
| F2 | pedido por voz (texto) -> sessão e carrinho | — |
| F3 | sessão de teste apagada e conferida (404) | — |

## Aceitação pelo Kafka (`a7.sh testar`)

"Esperado" é o resultado previsto com o código fixado no `a7.env` (13/11/2026). BLOQUEADO e AVISO
não reprovam; "(entrada simulada: X)" quer dizer que o teste publica a mensagem que X publicaria,
porque X ainda não existe no Kafka.

| Item | Verificação | Esperado | Obtido | Observação |
|---|---|---|---|---|
| C01 | A7 no ar | PASSOU | — |  |
| C02 | Sessão da fala (I5 simulado) | PASSOU | — |  |
| C03 | Item no carrinho | PASSOU ou AVISO | — | sem Ollama, depende do RapidFuzz |
| C04 | I5 real transcreve | PASSOU | — | 1ª vez baixa ~1 GB |
| C05 | Sessão da fala real | PASSOU | — |  |
| C06 | Áudio do P5 | BLOQUEADO | — | P5 sem Kafka |
| C07 | Métricas do S5 | BLOQUEADO | — |  |
| C08 | Envelope 1.0 | FALHOU (provável) | — | payload do I5 fora da 6c |
| C09 | Payload do I5 na 6c | AVISO | — |  |

## Conclusão

— (preencher depois da execução na Jetson)

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
