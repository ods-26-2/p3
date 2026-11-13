# Relatório de validação do A5 · EPI / segurança

**Situação:** não executado na Jetson. Preencha a coluna "Obtido" com a execução na placa e
copie as saídas para `evidencias/`.

| Item | Valor |
|---|---|
| Build | `builds/a5/` (commits em `a5.env`) |
| Data da execução | — |
| Placa | Jetson Orin `ods-pc`, JetPack 6.2.1 |
| Kafka | da turma, `172.18.4.56:9093` |

## Critérios de sistema (`validar-sistema.sh a5`)

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

## Fluxo pela API (`validar-a5-fluxo.sh`)

| ID | Verificação | Obtido |
|---|---|---|
| F1 | interface e saúde pelo nginx | — |
| F2 | 401 com senha errada e sem login | — |
| F3 | login, sessão, alertas, catálogo, zonas e logout | — |

## Aceitação pelo Kafka (`a5.sh testar`)

"Esperado" é o resultado previsto com o código fixado no `a5.env` (13/11/2026). BLOQUEADO e AVISO
não reprovam; "(entrada simulada: X)" quer dizer que o teste publica a mensagem que X publicaria,
porque X ainda não existe no Kafka.

| Item | Verificação | Esperado | Obtido | Observação |
|---|---|---|---|---|
| C01 | Login do administrador | PASSOU | — |  |
| C02 | S3 cria o alerta (S2 simulado) | PASSOU | — |  |
| C03 | S4 grava o evento | PASSOU | — | o S4 precisa de cam0.mp4 no buffer |
| C04 | Clipe no alerta | PASSOU ou AVISO | — |  |
| C05 | Alerta no A5 | PASSOU | — |  |
| C06 | Reconhecimento vira comando ao S3 | PASSOU | — |  |
| C07 | Alerta ACKNOWLEDGED | PASSOU | — |  |
| C08 | I9 avalia o EPI (I1 simulado) | PASSOU ou AVISO | — | o I9 pode esperar o PPE_CATALOG do A5 |
| C09 | Eventos de EPI do S2 | BLOQUEADO | — | S2 sem Kafka |
| C10 | Detecção real de EPI | BLOQUEADO | — | sem modelo |
| C11 | Envelope 1.0 | a confirmar | — |  |

## Conclusão

— (preencher depois da execução na Jetson)

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
