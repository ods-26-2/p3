# Relatório de validação do A4 · Esporte / arbitragem

**Situação:** não executado na Jetson. Preencha a coluna "Obtido" com a execução na placa e
copie as saídas para `evidencias/`.

| Item | Valor |
|---|---|
| Build | `builds/a4/` (commits em `a4.env`) |
| Data da execução | — |
| Placa | Jetson Orin `ods-pc`, JetPack 6.2.1 |
| Kafka | da turma, `172.18.4.56:9093` |

## Critérios de sistema (`validar-sistema.sh a4`)

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

## Fluxo pela API (`validar-a4-fluxo.sh`)

| ID | Verificação | Obtido |
|---|---|---|
| F1 | saúde: Kafka ligado, sem modo demo, token exigido | — |
| F2 | 401 sem token e com token errado; 422 de ângulo fora da faixa | — |
| F3 | 404 de partida inexistente; estado da câmera e do player | — |
| F4 | interface | — |

## Aceitação pelo Kafka (`a4.sh testar`)

"Esperado" é o resultado previsto com o código fixado no `a4.env` (13/11/2026). BLOQUEADO e AVISO
não reprovam; "(entrada simulada: X)" quer dizer que o teste publica a mensagem que X publicaria,
porque X ainda não existe no Kafka.

| Item | Verificação | Esperado | Obtido | Observação |
|---|---|---|---|---|
| C01 | API com Kafka | PASSOU | — |  |
| C02 | Partida criada | PASSOU | — |  |
| C03 | Calibração do I3 | PASSOU | — |  |
| C04 | A4 carregou a calibração | PASSOU | — |  |
| C05 | Comando de ângulo | PASSOU | — |  |
| C06 | P7 responde | BLOQUEADO | — | P7 sem Kafka |
| C07 | Sessão do vídeo | PASSOU | — |  |
| C08 | I1 detecta a bola | a confirmar | — | depende do vídeo e do modelo app-volei |
| C09–C11 | I2, S1 e player | a confirmar | — |  |
| C12 | Lance decidido | AVISO provável | — | precisa de quique visível e calibração do mesmo vídeo |
| C13 | Replay pelo S4 | a confirmar | — | só roda se houver lance |
| C14 | Envelope 1.0 | FALHOU (provável) | — | envelope do P4 |

## Conclusão

— (preencher depois da execução na Jetson)

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
