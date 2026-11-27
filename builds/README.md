# Builds das aplicações ODS (P3 · SIS-1)

Uma pasta por aplicação. Cada uma sobe a aplicação com a cadeia de componentes que ela de fato
consome hoje, com um comando, e se remove com outro. Só uma build cabe no cartão da Jetson por vez.

## Uso na Jetson

```bash
cd /opt/ods/p3/builds
./ods.sh lista            # o que cada build ocupa na placa
./ods.sh trocar a5        # remove as outras builds (mantém as imagens que o A5 usa) e sobe o A5
```

Dentro de cada pasta (`builds/<app>/`):

| Comando | O que faz |
|---|---|
| `./<app>.sh` | confere disco, segredos e Kafka; baixa o código nos commits do `<app>.env`; constrói só o que falta, em etapas, limpando o cache; sobe e espera |
| `./<app>.sh testar` | teste de aceitação pelo Kafka da turma (serviço `aceite`, validador do B4) → `resultados/aceite-<app>-*.txt` e `.json` |
| `./<app>.sh status` / `parar` | estado / derruba (volumes ficam) |
| `./limpar.sh` | remove containers (volumes ficam) |
| `./limpar.sh --imagens [--manter <app>]` | também as imagens da build e o cache de build |
| `./limpar.sh --dados` | também os volumes (pede para digitar o nome da app) |
| `./limpar.sh --codigo` | também os clones que nenhuma outra build usa |

Antes da primeira subida: `cp <app>.secrets.env.exemplo <app>.secrets.env` e preencha (A1, A2, A4, A5, A8).

## Aplicações

| App | Sobe por padrão | Sob demanda | Portas | Fora (motivo) |
|---|---|---|---|---|
| A1 | a1-db, a1-backend, a1-frontend, s4 | `./a1.sh i8` (eventos de exemplo do I8) · perfil `cadeia`: s5 | 5500 | P4/I1 (I8 não consome), P7 (sem Kafka) |
| A2 | a2, a2-cracha (web-app com Dockerfile do VER-2), i6, s4 | — | 8000, 8001, 8082 | P4 (I6 não lê o P4) |
| A3 | a3, s3, i2, s1 | `./a3.sh video` (p4+i1) · `./a3.sh cadeia` (s4, s5) | 8501 | S2 (sem Kafka) |
| A4 | a4-back, a4-front, i2, s1, s4 | `./a4.sh calibrar` (i3) · `./a4.sh video` (p4+i1 com modelo app-volei) · `cadeia`: s5 | 3000, 8000, 18084 | P7 (sem Kafka) |
| A5 | a5-backend, a5-frontend, s3, s4 | `./a5.sh cadeia` (i9, i2, s1) · `./a5.sh video` (p4 + i1 na GPU com o modelo de EPI `app-epi`; vídeo `VIDEO_ARQUIVO`) | 8095 | S2 (sem Kafka) |
| A6 | a6, s6 (do repo i4) | `./a6.sh amostra` (sinal do léxico como I4) | 8086 | I4 ao vivo (servidor C++ próprio), P4/P5/S4 |
| A7 | a7 | `./a7.sh fala` (I5 transcreve um áudio) | 8000 | P5 (sem Kafka), S3/S4/S5 |
| A8 | ver `a8/` (validada na Jetson em 12/11/2026) | | 3000, 8081 | S2 |

## Serviços permanentes

| Build | Sobe | Uso | Guia |
|---|---|---|---|
| `i1/` | `kafka-topicos`, `i1` (orquestrador do I1 `3b2a9cc`, GPU, `restart: unless-stopped`) · `./i1.sh engines` (engines de `I1_PACOTES`) | Fica de pé enquanto as aplicações trocam. Pedidos em `ods.i1.command` (`START`/`HEARTBEAT`/`STOP` por equipe), detecções em `ods.i1.detections`. O `./ods.sh trocar` não a remove, e o `limpar.sh --imagens` das apps mantém a imagem dela | [`validacao/i1/GUIA-BUILD-I1.md`](../validacao/i1/GUIA-BUILD-I1.md) |

## Build de todas as inferências

| Build | Sobe por padrão | Sob demanda | Portas | Guia |
|---|---|---|---|---|
| `inf/` | `i2`, `i4-server` + `i4` (Libras ao vivo), `i6` (QR, vídeo em laço), `i9` | `./inf.sh i1 [EQUIPE]` (pedido ao I1 de `i1/`) · `i3` (calibração da quadra do A4) · `i4` (vídeo como webcam) · `i7` (placas em vídeo, detector na GPU) · `i8` (eventos de exemplo) · `./inf.sh testar` dispara todas e confere cada tópico | 18080 (servidor do I4, só `127.0.0.1` por padrão) | [`validacao/inf/GUIA-BUILD-INF.md`](../validacao/inf/GUIA-BUILD-INF.md) |

Sem `i1` próprio: o I1 é o de `i1/` (tem de estar de pé e no mesmo Kafka; o `inf.sh` confere). Entra no
`./ods.sh trocar inf` como as aplicações. GPU: o I1 e o detector do I7 (mesma engine `app-plates` do I1); o resto em CPU.

## Build inf_a4: só I1, I2 e I3 (camada 1-2 do A4)

| Build | Sobe por padrão | Sob demanda | Testes | Guia |
|---|---|---|---|---|
| `inf_a4/` | `i1` (orquestrador **próprio**, GPU) + `i2` | `./inf_a4.sh i1 [EQUIPE] [QUADROS]` · `i3` (calibração da quadra do A4) | `./inf_a4.sh testar` (cadeia I1 → I2, I3 e contrato com o schema de cada repositório) · `./inf_a4.sh repos` (suítes das equipes nas imagens) | [`validacao/inf_a4/GUIA-BUILD-INF-A4.md`](../validacao/inf_a4/GUIA-BUILD-INF-A4.md) |

Kafka **da nuvem** (`34.66.235.91:9093`); o container `kafka` da placa tem de continuar rodando (a build confere e avisa).
Broker da placa só por `inf_a4.local.env`. A imagem do I1 é a mesma do `i1/` (`ods-i1-gpu:<I1_REF>`): não
reconstrói. Recusa subir se o I1 permanente estiver de pé no mesmo broker.
Chamava-se `inf_restrita` até 26/11/2026. Guardar no notebook e subir de lá sem reconstruir (rodam no
notebook, por ssh): `./guardar-no-notebook.sh` e `./subir-do-notebook.sh [pasta]` (guia, seção 4.1).

## Estrutura comum

- `comum/lib.sh`: funções de subir/status/parar/limpar usadas pelos `<app>.sh` e `limpar.sh`.
- `comum/preparar-codigo.sh`: clona todo `<REPO>_REF` do `.env` no commit fixado.
- `comum/kafka_override/`: contorno para código com broker fixo (hoje só o A3).
- `comum/aceite/ods_aceite.py`: biblioteca dos testes de aceitação (`<app>/aceite/aceite_<app>.py`).
  Quando o produtor real não existe no Kafka (S2, modelo de EPI…), o teste injeta a mensagem e o item diz "(entrada simulada: X)".

Validação de sistema (S1–S9) e fluxo pela API de cada app: `validacao/` (ver `validacao/<app>/README.md`).

Nada aqui altera o código das equipes: contornos ficam no compose, comentados com o motivo e como desfazer.
