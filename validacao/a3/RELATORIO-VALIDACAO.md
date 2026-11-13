# Relatório de validação do A3 · Monitoramento / eventos

**Situação:** não executado na Jetson. Preencha a coluna "Obtido" com a execução na placa e
copie as saídas para `evidencias/`.

| Item | Valor |
|---|---|
| Build | `builds/a3/` (commits em `a3.env`) |
| Data da execução | — |
| Placa | Jetson Orin `ods-pc`, JetPack 6.2.1 |
| Kafka | da turma, `172.18.4.56:9093` |

## Critérios de sistema (`validar-sistema.sh a3`)

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

## Fluxo pela API (`validar-a3-fluxo.sh`)

| ID | Verificação | Obtido |
|---|---|---|
| F1 | saúde do Streamlit e página | — |
| F2 | contorno do broker fixo presente no container | — |

## Aceitação pelo Kafka (`a3.sh testar`)

"Esperado" é o resultado previsto com o código fixado no `a3.env` (13/11/2026). BLOQUEADO e AVISO
não reprovam; "(entrada simulada: X)" quer dizer que o teste publica a mensagem que X publicaria,
porque X ainda não existe no Kafka.

| Item | Verificação | Esperado | Obtido | Observação |
|---|---|---|---|---|
| C01 | Painel no ar | PASSOU | — |  |
| C02 | A3 decide e pede alerta (S2 simulado) | PASSOU | — | exige o painel aberto no navegador |
| C03 | S3 aceita o comando | PASSOU | — |  |
| C04 | Alerta publicado | PASSOU | — |  |
| C05 | Histórico do S3 | PASSOU | — |  |
| C06 | Sessão do vídeo | PASSOU | — |  |
| C07–C09 | I1, I2, S1 na sessão | PASSOU | — |  |
| C10 | Transições de zona | PASSOU ou AVISO | — | depende de algo cruzar a metade do quadro |
| C11 | Eventos do S2 pela cadeia | BLOQUEADO | — | S2 sem Kafka |
| C12 | Detecção de pessoas | AVISO | — | modelo de placas |
| C13 | Envelope 1.0 | FALHOU (provável) | — | o P4 publica com o envelope do guia, como no C18 do A8 |

## Conclusão

— (preencher depois da execução na Jetson)

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
