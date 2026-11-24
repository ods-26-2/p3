# Guia de teste — build dedicada do I1 (serviço permanente na Jetson)

Build em [`builds/i1/`](../../builds/i1/). Deixa o I1 **sempre de pé** na Jetson, atendendo pedidos de detecção pelo Kafka. As builds das aplicações e a futura build de "todas as inferências" usam este I1 em vez de subir um próprio.

**Estado (23/11/2026):** escrita e simulada fora da placa. **Ainda não rodou na Jetson.** O que foi validado e onde está na seção 9.

**Arranjo da turma (23/11/2026):** as aplicações rodam na nuvem; a Jetson roda as inferências. O I1 usa o **Kafka da nuvem** (`34.66.235.91:9093`, `KAFKA_BROKER` no `i1.env`), não o container `kafka` da placa.

---

## 1. O que mudou no I1 e o que a build faz

O commit `3b2a9cc` da develop do I1 (20/11/2026) trouxe um **orquestrador** (`I1/run_orchestrator.py` e `I1/detector/orchestrator.py`):

- **Escuta comandos** em `ods.i1.command`: `START`, `HEARTBEAT` e `STOP`.
- **Atende um pedido por vez,** em fila FIFO, com **um só modelo carregado na GPU**. Antes de carregar o próximo, libera o anterior (`p2.release`).
- **Escolhe o modelo pela equipe** que pede:

  | `squad` | App | Pacote B5 | Classes |
  |---|---|---|---|
  | `VER5` | A8 | `app-plates/1.0.0` | 4 tipos de placa |
  | `VER3` | A5 | `app-epi/1.0.0` | pessoa, capacete, colete |
  | `VER6` | A3 | `app-epi/1.0.0` | só pessoa |
  | `VER1` | A1 | `app-industry/1.0.0` | peca |
  | `INV1` | A4 | `app-sports/1.2.0` (entrada 1280) | ball |

- **Lê o vídeo da equipe:** `VIDEO_DIR/<SQUAD>.mp4`, um arquivo indicado no comando (`"source"`) ou os quadros do P4 pela memória compartilhada (`"source": "video" | "imx519" | "imx477"`).
- **Publica** em `ods.i1.detections`. O `source_id` é o do comando ou, sem ele, o nome da equipe.
- **Encerra o pedido** no fim do vídeo, ao atingir `max_frames`, com `STOP` ou quando o TTL vence sem `HEARTBEAT` (padrão: 60 s).

O pipeline de detecção, o `Dockerfile.jetson` e a ingestão **não mudaram** desde o `cb5c381` validado no A8.

**A build** ([`docker-compose.yml`](../../builds/i1/docker-compose.yml), projeto `ods-i1`):

| Serviço | Papel |
|---|---|
| `kafka-topicos` | One-shot: cria `ods.i1.command` e `ods.i1.detections` no Kafka da turma |
| `i1` | O orquestrador. `restart: unless-stopped`, GPU (`runtime: nvidia`, `P2_BACKEND=trt`), log com rotação (3 × 10 MB) |
| `i1-engine` | One-shot (perfil `engine`): confere ou compila a engine FP16 de cada pacote de `I1_PACOTES` |
| `aceite` | Perfil `aceite`: o teste. Usa a própria imagem do I1, então não há imagem extra para construir |

**Contorno do P3:** a base da imagem é a `l4t-tensorrt` em vez da `l4t-jetpack`, como no A8.

---

## 2. Antes de começar (na Jetson)

```bash
cd /opt/ods/p3 && git pull
df -h /                                   # precisa de ~4 GB livres + ~2,5 GB para a imagem nova
docker run --rm confluentinc/cp-kafka:latest kafka-broker-api-versions \
  --bootstrap-server 34.66.235.91:9093 2>/dev/null | grep -m1 'id:'   # deve terminar em "-> ("
```

**Kafka da nuvem:** em 23/11/2026, a porta 9093 do broker **recusou a conexão** a partir do computador do usuário (fora do laboratório). Pode ter sido queda momentânea ou firewall liberando só a rede do laboratório. Se o comando acima não responder na Jetson, o `./i1.sh` para na conferência com essa mensagem. Na Jetson ele também não respondeu (23/11/2026): o broker do GCP estava desligado.

**Testar no Kafka da placa** (decisão do usuário, 23/11/2026, enquanto o da nuvem está fora): sem editar o `i1.env` versionado (isso travaria o `git pull`), use o `i1.local.env`, que fica fora do Git e vale no lugar do `i1.env`:

```bash
docker ps -a --filter name='^kafka$' --format '{{.Status}}'    # o Kafka da turma na placa precisa estar "Up"
cd /opt/ods/p3/builds/i1
cp i1.local.env.exemplo i1.local.env                           # KAFKA_BROKER=172.18.4.56:9093, KAFKA_CONTAINER=kafka
```

O `./i1.sh status` mostra de onde veio o broker. Para voltar à nuvem: `rm i1.local.env` e `./i1.sh` (o container é recriado com o broker novo). Com o Kafka da placa, troque `34.66.235.91:9093` por `172.18.4.56:9093` nos comandos manuais deste guia (consumidor da seção 4).

**Imagem nova.** O `I1_REF` é o `3b2a9cc`, o mesmo agora fixado no A8 e no A5: a placa fica com uma imagem `ods-i1-gpu` só (~2,1 GB). Se a antiga `ods-i1-gpu:cb5c381` ainda estiver na placa e faltar disco, ela pode sair: `docker rmi ods-i1-gpu:cb5c381` (sem `-f`; não sai se algum container a usar).

**Vídeos das equipes.** Ficam versionados em `assets/` na raiz do p3 (`VER1.mp4`, `INV1.mp4`, `epi.mp4`); o `cam0.mp4` do VER5 já está na placa (A8). O `./i1.sh` copia os vídeos para `VIDEO_DIR` (`/var/lib/ods/videos`) e cria os links `<SQUAD>.mp4` que o orquestrador procura quando o pedido não traz `"source"`. Para fazer só isso:

```bash
cd /opt/ods/p3/builds/i1
./i1.sh videos
ls -l /var/lib/ods/videos      # VER1.mp4, INV1.mp4, epi.mp4, cam0.mp4 + links VER3/VER5/VER6.mp4
```

| Equipe | Vídeo | Formato |
|---|---|---|
| VER5 (A8) | `cam0.mp4` (na placa) | 1280x720, 10 quadros/s |
| VER3 (A5), VER6 (A3) | `epi.mp4` | 1920x1080, 24 quadros/s, 8 s |
| VER1 (A1) | `VER1.mp4` | **3840x2160**, 30 quadros/s, 8,5 s: a decodificação em CPU de 4K deve ser o gargalo |
| INV1 (A4) | `INV1.mp4` | 1920x1080, 30 quadros/s, 32 s |

O mapa está em `I1_VIDEOS` no `i1.env`. Se `VIDEO_DIR` não for gravável pelo usuário `ods`: `sudo chown ods /var/lib/ods/videos`. Um `epi.mp4` diferente já na pasta (do A5) é substituído pelo de `assets/`.

---

## 3. Passo 1 — subir

```bash
cd /opt/ods/p3/builds/i1
./i1.sh
```

**O que acontece:**
1. **Confere a placa:** disco, se o Kafka da nuvem responde, runtime `nvidia` e as pastas `I1_ENGINES_DIR`, `I1_P4_DIR` e `VIDEO_DIR`. Também avisa quais vídeos de teste faltam.
2. **Clona o código:** `i1` e `b4` nos commits do `i1.env`, em `/opt/ods/src`.
3. **Copia os vídeos** de `assets/` (como em `./i1.sh videos`).
4. **Constrói `ods-i1-gpu:3b2a9cc`,** se ela não existir (~15–25 min), e roda `docker builder prune -af` em seguida.
5. **Sobe** o `kafka-topicos` e o `i1`.
6. **Prepara as engines:**
   - `app-plates` e `app-epi` já existem (A8 e A5), então só são conferidas, em segundos.
   - `app-industry` e `app-sports` compilam na primeira vez, **~7 min cada**. O sports, com entrada 1280, pode levar mais e usar mais memória.
   - Antes de compilar, o script esvazia o cache de páginas, o que pede `sudo`.
7. **Espera a linha** `[I1-ORCH] Aguardando comandos em 'ods.i1.command'` no log.

**Esperado no fim:** `✔ I1 pronto: ...` e o exemplo de comando.

**Se interromper:** rode `./i1.sh` de novo. Ele não reconstrói a imagem que já existe nem recompila as engines que carregam.

**Conferência rápida:**

```bash
./i1.sh status
```

Deve mostrar:
- `i1  running`;
- `Reinícios do i1: 0`;
- `Atendendo agora: nada (GPU livre)`;
- os 5 vídeos e as 4 engines com `✔`.

**Anote** a `Memória do i1` em repouso. Como nenhum modelo fica carregado parado, deve ficar bem abaixo do que o I1 usava no A8.

---

## 4. Passo 2 — um pedido à mão

Em um terminal, acompanhe o log:

```bash
./i1.sh log
```

Em outro, mande um pedido e leia as detecções:

```bash
cd /opt/ods/p3/builds/i1
./i1.sh comando '{"action": "START", "squad": "VER5", "source_id": "teste-manual", "max_frames": 50}'

docker run --rm confluentinc/cp-kafka:latest kafka-console-consumer \
  --bootstrap-server 34.66.235.91:9093 --topic ods.i1.detections --max-messages 3 \
  --property print.key=true | cut -c1-300
```

Rode o consumidor logo depois do comando: ele só lê as mensagens novas. Sem `"source"`, o I1 lê `/videos/VER5.mp4` (o link para o `cam0.mp4`); isso também prova que os links funcionam dentro do container.

**Esperado no log:**
1. `Equipe 'VER5' ... enfileirada`.
2. `Carregando 'app-plates-1.0.0' (A8) para equipe 'VER5'`.
3. Linhas por quadro.
4. `Sessão 'VER5' encerrada (max_frames_reached) | quadros publicados: 50`.

**Esperado nas mensagens:**
- a chave é `teste-manual`;
- `"artifact_version": "app-plates-1.0.0-fp16"`. O `-fp16` é a prova de que rodou no TensorRT, sem cair para a CPU.

**Prova extra de GPU (opcional),** enquanto um pedido longo roda (sem `max_frames`):
- `tegrastats` mostra `GR3D_FREQ` acima de 0%;
- `sudo grep -c libnvinfer /proc/$(docker inspect -f '{{.State.Pid}}' ods-i1-i1-1)/maps` dá mais que 0.

Para encerrar um pedido longo: `./i1.sh comando '{"action": "STOP", "squad": "VER5"}'`.

---

## 4b. Testes do repositório do I1 (opcional, recomendado)

O `./i1.sh testar` (seção 5) é o teste de aceitação do P3: trata o I1 como caixa-preta, pelo Kafka. Os testes **do próprio repositório** (`I1/tests`, inclusive os 6 do orquestrador) rodam à parte, dentro de um container com a mesma imagem, GPU, variáveis e engines do serviço `i1`, sem publicar no Kafka:

```bash
cd /opt/ods/p3/validacao/i1
./testar-i1-servico.sh            # serviço i1 da build dedicada (padrão); --build a8 para o do A8
```

| Item | Esperado |
|---|---|
| S01 | Imagem `ods-i1-gpu:3b2a9cc…` existe e bate com o `I1_REF` do `i1.env` |
| S02 | 45 de 46 testes ok; só o `test_05` dá erro, esperado: precisa do `ultralytics` (caminho de CPU), que a imagem Jetson não instala (conferido fora da placa em 23/11/2026) |
| S03 | `CMD` padrão da imagem (`run_detector` nas 9 fixtures de placas, saída em stdout): código 0, mensagens com `artifact_version` `app-plates-1.0.0-fp16` |

Relatório: `validacao/i1/resultados/i1-servico-<data>.txt`.

## 5. Passo 3 — teste de aceitação

```bash
./i1.sh testar
```

O teste leva ~3–5 min. Antes de começar:
- avisa se o I1 estiver atendendo outro pedido (os do teste entram na fila);
- esvazia o cache de páginas (pede `sudo`).

Cada pedido do teste usa um `source_id` `p3-teste-*` e um `session_id` próprio. **Cuidado:** o Kafka é o da nuvem, compartilhado pela turma.
- Qualquer consumidor de `ods.i1.detections` (I2 de outras equipes, aplicações na nuvem) também recebe as detecções do teste. Pelo `source_id` elas não caem nas zonas de ninguém, mas avise a turma antes.
- O teste manda `STOP` para `VER5` (T31). Se uma aplicação real estiver usando o I1 como VER5 nesse momento, o pedido dela também para.

**Itens e resultado esperado hoje:**

| Item | Confere | Esperado |
|---|---|---|
| T01 | `ods.i1.command` e `ods.i1.detections` existem | PASSOU |
| T1-VER5 | `app-plates` carrega e roda: `artifact_version …-fp16`, classes do pacote, schema do I1, `sequence` sem lacunas | PASSOU |
| T1-VER3 / T1-VER6 | `app-epi` (VER6 só com `pessoa`) sobre o `epi.mp4` | PASSOU |
| T1-VER1 / T1-INV1 | `app-industry` sobre o `VER1.mp4`, `app-sports` sobre o `INV1.mp4` | PASSOU. AVISO se nenhum objeto aparecer nos 30 primeiros quadros (ex.: bola fora de cena no início) |
| T20 | Fila FIFO: as 5 equipes atendidas na ordem, sem sobreposição | PASSOU |
| T21 | Tempo de troca de modelo (fim de uma equipe → 1ª detecção da seguinte) | PASSOU até 15 s; acima, AVISO. **Anote os valores** |
| T22 | Envelope 1.0 pelo validador do B4 | PASSOU (o I1 já valida contra o próprio schema antes de publicar) |
| T31 | `STOP` interrompe a equipe ativa em até 2 s | PASSOU |
| T32 | Sem `HEARTBEAT`, o pedido para no TTL (4 s no teste) | PASSOU. AVISO se a engine levar mais de 4 s para carregar: o relógio do TTL começa **antes** da carga |
| T33 | Com `HEARTBEAT` a cada 1,5 s, o pedido vai até o fim do vídeo | PASSOU. AVISO se o vídeo acabar antes de 5 s |
| T02 | JSON quebrado e equipe desconhecida são ignorados (`Comando ignorado` no log) | PASSOU |
| T30 | Vídeo inexistente vira `error` no log, e o I1 segue atendendo | PASSOU |
| T40 | Motivos de encerramento no log batem com cada pedido | PASSOU |
| T41 | O container não reiniciou (`RestartCount` igual antes e depois) | PASSOU |
| T42 | Sem `OUT_OF_MEMORY` / `NvMap ... error 12` no log | PASSOU. AVISO indica pouca memória: veja a seção 8 |

**Saída:**
- `resultados/aceite-i1-<data>.txt` e `.json`;
- o `.json` traz, por pedido, o tempo do START até a 1ª mensagem, as classes vistas e as trocas de modelo.

**Código 0** = nenhum item FALHOU.

---

## 6. Passo 4 — "sempre pronto" (resiliência)

**R1 — queda do processo.** Simula um defeito que derruba o I1:

```bash
C=$(docker compose --env-file i1.env -p ods-i1 ps -q i1)
docker inspect -f '{{.RestartCount}}' $C                 # anote
sudo kill -9 $(docker inspect -f '{{.State.Pid}}' $C)
sleep 10; docker inspect -f '{{.State.Status}} {{.RestartCount}}' $C   # running, contagem +1
docker logs --tail 5 $C | grep 'Aguardando comandos'
```

Depois, repita o pedido da seção 4: deve funcionar sem intervenção.

**Não use `docker stop`/`docker kill`:** o Docker trata isso como parada manual e não religa o container.

**R2 — reinício da placa.** Com o Kafka na nuvem, o I1 não depende de nenhum container da placa. Depois do boot:

```bash
docker ps -a --format '{{.Names}} {{.Status}}' | grep '^ods-i1'
```

- **Esperado:** `ods-i1-i1-1 Up`, porque o `unless-stopped` religa o I1. Repita o pedido da seção 4: deve funcionar sem intervenção.
- **Rede ainda fora do ar no boot:** o I1 fica de pé tentando conectar e volta a atender sozinho quando a rede volta.
- **Pasta de sockets:** `I1_P4_DIR` fica em `/var/lib/ods`, não em `/tmp`, para o bind existir depois do boot.
- **Containers de outros grupos:** o container `kafka` da placa (de outro grupo, `restart: no`) não volta sozinho; isso não afeta o I1, mas avise o dono antes de reiniciar.

**R3 — trocar de aplicação não derruba o I1:**

```bash
cd /opt/ods/p3/builds
./ods.sh lista        # a linha "i1" aparece
```

O `./ods.sh trocar <app>`:
- só remove builds `a*`;
- o `limpar.sh --imagens` delas não remove `ods-i1-gpu:<I1_REF do i1.env>`, que aparece como `mantida (o i1 usa)`.

---

## 7. Como as outras builds usam este I1 (contrato provisório)

**Comandos.** JSON simples em `ods.i1.command`. A chave da mensagem é livre; o utilitário usa o nome da equipe.

```json
{"action": "START", "squad": "VER5", "source_id": "file_cam0", "source": "/videos/cam0.mp4",
 "ttl_seconds": 120, "max_frames": 1000, "session_id": "<uuid4>"}
{"action": "HEARTBEAT", "squad": "VER5", "ttl_seconds": 120}
{"action": "STOP", "squad": "VER5"}
```

- **`squad`:** aceita também `app_id` (`"A8"`) ou `artifact_id`.
- **`source_id`:** mande sempre. Sem ele, o `source_id` vira `"VER5"`, que não bate com as zonas do S1 (`file_cam0`…).
- **`"force": true`:** passa na frente e interrompe quem está na GPU.
- **Pedido longo:** mande `HEARTBEAT` antes do TTL vencer (60 s por padrão).
- **Mesma equipe:** um `START` da equipe que já está ativa **só renova o TTL**. A fonte e os parâmetros novos são ignorados até ela terminar.

**Quadros do P4 ao vivo** (`"source": "video"`, `"imx519"` ou `"imx477"`):
- o P4 da outra build precisa de `ipc: host`;
- a pasta `I1_P4_DIR` do host (`/var/lib/ods/p4-shm`) precisa estar montada em `/tmp`, como no I1;
- nesse modo, o `source_id` e o `session_id` vêm do cabeçalho `P4R1` do P4, não do comando.

**Detecções:** leia `ods.i1.detections` filtrando por `source_id` ou `session_id`.

**GPU compartilhada:**
- **Na GPU:** o I1 desta build carrega um modelo por vez. Não rode ao mesmo tempo o `i1` próprio do A8/A5 (perfil `video`): dois contextos TensorRT no Orin Nano (7,4 GB divididos com a CPU) já deram `OUT_OF_MEMORY` (14/11/2026).
- **Builds novas:** a de inferências **não** deve ter serviço `i1`.

---

## 8. Se algo der errado

| Sintoma | Olhar |
|---|---|
| `o Kafka não responde em 34.66.235.91:9093` | Broker da nuvem fora do ar ou porta bloqueada para a rede da placa. Teste à mão com `kafka-broker-api-versions` (seção 2) e confirme o endereço com a turma |
| Pedido sem nenhuma detecção | `./i1.sh log`: `Nenhum vídeo encontrado para 'X'` (rode `./i1.sh videos` ou mande `"source"`), `ENGINE_NOT_FOUND` (rode `./i1.sh engines`) ou `ttl_expired` logo após carregar (TTL curto demais) |
| `OUT_OF_MEMORY` / `NvMap ... error 12` | Outra pilha usando a GPU (A8/A5 com vídeo, A5 compilando engine). `sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'` e repita |
| Pedido antigo roda sozinho depois de religar o I1 | O grupo `ods-i1-orchestrator` guarda o offset: comandos enviados com o I1 parado são atendidos quando ele volta (seção 10) |
| Container em laço de reinício | `docker logs --tail 50 ods-i1-i1-1`. O orquestrador só trata alguns tipos de erro por pedido; outros derrubam o processo, e a fila em memória se perde |

**Desfazer:**
- `./i1.sh parar`: as aplicações perdem o I1;
- `./limpar.sh --imagens`: remove também a imagem. As engines em `/var/lib/ods/engines` ficam, porque são as mesmas do A8/A5.

---

## 9. O que foi validado e onde

**Fora da Jetson (23/11/2026, computador do usuário):**
- `bash -n` em `i1.sh`, `limpar.sh`, `preparar-codigo.sh`, `comum/lib.sh` e `ods.sh`;
- YAML do compose e todas as variáveis definidas no `i1.env` (com `pyyaml`). **Sem `docker compose config`**: o plugin não está instalado aqui;
- suíte `I1/tests/test_orchestrator.py` do `3b2a9cc`: 6/6 OK;
- simulação do teste inteiro (`scratchpad/sim-i1`): o **orquestrador real** do `3b2a9cc` com um `p2` falso (devolve `engine_version <ref>-fp16`) e um Kafka falso em arquivo, mais o `aceite_i1.py` e o validador do B4 (`bb2ea8c`):
  - cenário normal: PASSOU 15, AVISO 2 (VER1/INV1 sem vídeo próprio), código 0;
  - engine do sports ausente: T1-INV1 e T40 FALHOU, como deveriam.

- `./i1.sh videos` numa cópia da build: copia os 3 vídeos de `assets/`, cria os links VER3/VER5/VER6 e, na 2ª vez, não copia de novo;
- `checar_kafka` da lib com `docker` falso: broker remoto (sem procurar o container `kafka`), broker fora do ar (para com mensagem) e A5 (continua exigindo o `kafka` local);
- vídeos de `assets/` com `ffprobe`: os três em H.264;
- broker da nuvem a partir do computador do usuário: **conexão recusada** na 9093 (seção 2).

**Não validado:**
- build da imagem e GPU de verdade;
- tempo de carga e de troca de cada engine (o falso usa 1 s);
- memória;
- compilação do `app-industry` e do `app-sports`;
- `ipc: host` com um P4 de outra build;
- reinício da placa;
- `shellcheck`.

**Para trazer de volta da Jetson:**
1. a saída do `./i1.sh` (o final, com as engines);
2. `./i1.sh status`;
3. o log do pedido manual da seção 4;
4. `resultados/aceite-i1-*.txt`;
5. o R1 da seção 6;
6. `df -h /` antes e depois.

---

## 10. Pontos em aberto

**Decididos em 23/11/2026:**
- **Broker:** aplicações na nuvem, inferências na Jetson → o I1 usa o Kafka da nuvem.
- **A8 e A5 no `3b2a9cc`:** `I1_REF` trocado nos dois `.env` (uma imagem só). Eles ainda usam o Kafka da placa e **não foram testados** com o I1 novo; o `run_detector.py` que eles usam não mudou.
- **Vídeos:** versionados em `assets/` e instalados pelo `./i1.sh videos`.

**Recados para o MOD-1 (I1):**
- **Contrato:** `ods.i1.command` não está na 6c nem no B1. Falta um schema, e o comando hoje não usa o envelope 1.0.
- **Caminhos e broker fixos:** o padrão do broker é o da nuvem, e a pasta de vídeos é `/home/sys2/SIS-2/videos`.
- **TTL:** o relógio começa antes de `p2.load`, então uma engine lenta (sports) consome parte do TTL.
- **Comandos antigos:** com auto-commit no grupo, comandos enviados com o I1 parado são executados quando ele volta, inclusive `START` antigos. Sugestão: descartar comandos mais velhos que o TTL.
- **Erros que derrubam o processo:** só `FileNotFoundError`, `RuntimeError`, `P2ExecutionError` e `ValueError` são tratados por pedido. Qualquer outro erro (ex.: `cv2.error`) derruba o processo e perde a fila.
- **`START` repetido:** um `START` da equipe ativa ignora a fonte e os parâmetros novos sem avisar.
- **Fim de pedido invisível:** não há mensagem no Kafka de "pedido aceito/encerrado". As aplicações só sabem que acabou porque as detecções param.
