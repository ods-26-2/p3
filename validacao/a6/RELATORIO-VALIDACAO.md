# Relatório de validação do A6 · Libras / acessibilidade

**Situação:** não executado na Jetson. Preencha a coluna "Obtido" com a execução na placa e
copie as saídas para `evidencias/`.

| Item | Valor |
|---|---|
| Build | `builds/a6/` (commits em `a6.env`) |
| Data da execução | — |
| Placa | Jetson Orin `ods-pc`, JetPack 6.2.1 |
| Kafka | da turma, `172.18.4.56:9093` |

## Critérios de sistema (`validar-sistema.sh a6`)

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

## Fluxo pela API (`validar-a6-fluxo.sh`)

| ID | Verificação | Obtido |
|---|---|---|
| F1 | página e estado (Kafka, léxico) | — |
| F2 | tradução português -> Libras | — |
| F3 | 404 de rota inexistente | — |
| F4 | trajetória do S6 na pasta compartilhada | — |

## Aceitação pelo Kafka (`a6.sh testar`)

"Esperado" é o resultado previsto com o código fixado no `a6.env` (13/11/2026). BLOQUEADO e AVISO
não reprovam; "(entrada simulada: X)" quer dizer que o teste publica a mensagem que X publicaria,
porque X ainda não existe no Kafka.

| Item | Verificação | Esperado | Obtido | Observação |
|---|---|---|---|---|
| C01 | A6 no ar e no Kafka | PASSOU | — |  |
| C02 | Sinal do I4 (amostra) | PASSOU | — |  |
| C03 | A6 recebeu o sinal | PASSOU | — |  |
| C04 | Comando de síntese | PASSOU | — |  |
| C05 | S6 responde | PASSOU | — |  |
| C06 | Trajetória compartilhada | PASSOU | — |  |
| C07 | Glosas do léxico do A6 que o S6 sabe sintetizar | AVISO | — | o S6 tem 20 sinais (MINDS-Libras); o léxico do A6 lista 100 |
| C08 | Tela mostra a síntese do S6 real | AVISO | — | a página usa o motor interno do A6; o S6 real só aparece no log |
| C09 | I4 ao vivo e captura | BLOQUEADO | — | servidor C++ do INV-2 fora da build |
| C10 | Envelope 1.0 | a confirmar | — | |

## Conclusão

— (preencher depois da execução na Jetson)

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
