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
| C01 | Login do administrador | PASSOU | PASSOU |  |
| C02 | S3 cria o alerta (S2 simulado) | PASSOU | PASSOU |  |
| C03 | S4 grava o evento | PASSOU | FALHOU | o S4 precisa do VIDEO_ARQUIVO no buffer |
| C04 | Clipe no alerta | PASSOU ou AVISO | AVISO |  |
| C05 | Alerta no A5 | PASSOU | PASSOU |  |
| C06 | Reconhecimento vira comando ao S3 | PASSOU | PASSOU |  |
| C07 | Alerta ACKNOWLEDGED | PASSOU | PASSOU |  |
| C08 | I9 avalia o EPI (I1 simulado) | PASSOU ou AVISO | PASSOU | o I9 pode esperar o PPE_CATALOG do A5 |
| C09 | Eventos de EPI do S2 | BLOQUEADO | BLOQUEADO | S2 sem Kafka |
| C10 | Detecção real de EPI (I1 na GPU, `app-epi-1.0.0-fp16`) | PASSOU | PASSOU (102 quadros, fp16) | AVISO se o vídeo não tiver pessoas; FALHOU se cair para CPU |
| C11 | Envelope 1.0 | a confirmar | FALHOU (I9 e session.started do P4) |  |
| C12 | I9 avalia o EPI das pessoas do vídeo | PASSOU | PASSOU (capacete INCORRETO 102/102) | sem calibração do I3 |
| C13 | Rastreio e zonas do vídeo (I2 → S1) | PASSOU (ponto na zona e transição) | PASSOU* (0 transições: zona 1280x720, vídeo 1920x1080) | zona de exemplo do P3, em pixels |

## Conclusão

Execução na Jetson em 18/11/2026 13:12 (`aceite-a5-20261118-131217`, coluna "Obtido"): PASSOU 9, FALHOU 2, BLOQUEADO 1, AVISO 1.

- A cadeia real roda na GPU: P4 → I1 (`app-epi-1.0.0-fp16`, 102 quadros 1920x1080) → I9 (102 avaliações) e I2 → S1 (100 com trilhas e posições).
- C06/C07 passaram com as permissões do S3 geradas pelo A5 (antes: 403 `UNAUTHORIZED_ACTOR`).
- *C13 passou pela regra antiga, mas nenhuma posição caiu na zona (zona 1280x720, vídeo 1920x1080). Corrigido com `zones-a5-p3-2` (1920x1080) e o C13 passou a exigir ponto na zona e transição: falta rodar de novo.
- C03: o S4 não gravou o clipe do evento simulado; falta o log do S4 (`S2 event ...`).
- C11: o I9 publica um evento por quadro com `persons[]` (o contrato 1.0 pede um por pessoa, com `detection_id`, `bbox`, `calibrated`, `items`); o `session.started` do P4 usa `occurred_at` (recados para VER-3 e SIS-2).
- C12: o I9 marcou capacete INCORRETO em todos os quadros (no quadro 83 o capacete está na parte de baixo da caixa da pessoa). A conferir num quadro do vídeo se é o vídeo ou a geometria do I9.

## Histórico

| Data | O que mudou |
|---|---|
| 2026-11-13 | Scripts de validação e teste de aceitação criados (P3); ainda não executados na placa |
