# CLAUDE.md — Builds das aplicações ODS 2026/2 (P3 · SIS-1)

Este arquivo é o contexto de trabalho do Claude Code para a frente **P3** (composição, build e ciclo de vida das aplicações) do projeto ODS 2026/2. Coloque-o na raiz do clone do repositório `ods-26-2/p3`.

---

## 0. Antes de qualquer coisa: registro de progresso (obrigatório)

O trabalho é longo e a máquina pode desligar no meio (queda de energia, sessão encerrada). Todo avanço precisa estar em disco, nunca só na conversa.

1. **No início de toda sessão:**
   - Se existir `temp/PROGRESSO.md`, leia o arquivo inteiro antes de fazer qualquer coisa e retome a partir de **"Próximo passo"**.
   - Se a pasta `temp/` não existir, crie com `mkdir -p temp`.
   - Se o arquivo não existir, crie `temp/PROGRESSO.md` com o modelo abaixo.
2. **Depois de cada passo significativo,** atualize o arquivo **imediatamente**. Contam como passo: uma decisão tomada, um arquivo criado ou alterado, um resultado de comando, um problema descoberto ou uma resposta do usuário que muda o plano. Não acumule para o fim.
3. **Antes de um comando demorado** (build, teste, download), registre o que vai rodar e como retomar se for interrompido.
4. **Mantenha o bloco "Estado atual" no topo** sempre reescrito com a situação presente. Abaixo dele, o **Registro** é só acréscimo: nunca apague entradas.
5. **Quando o Registro passar de ~500 linhas,** mova as entradas antigas para `temp/PROGRESSO-arquivo-AAAA-MM-DD.md` e deixe um link no lugar.
6. **`temp/` é diário de trabalho local.** Fica fora do Git (acrescente `temp/` ao `.gitignore` se ainda não estiver), a menos que o usuário peça para versionar.

Modelo de `temp/PROGRESSO.md`:

```markdown
# Progresso — builds ODS (P3)

## Estado atual
- Aplicação em foco: A?
- Fase: (levantamento | compose | script | teste | validado na Jetson)
- Último resultado: …
- Próximo passo: …
- Bloqueios / perguntas abertas ao usuário: …

## Registro
### AAAA-MM-DD HH:MM — <título curto>
- Feito: …
- Arquivos: …
- Resultado / evidência: …
- Próximo: …
```

---

## 1. Objetivo final

Gerar **uma pasta por aplicação principal (A1 a A8)** no repositório `p3`, cada uma capaz de subir a aplicação inteira, com toda a sua cadeia de dependências, com um comando só, e de limpá-la com outro:

```
builds/<app>/                      ex.: builds/a8/
├── <app>.sh                       sobe tudo: ./<app>.sh [subir|testar|status|parar]
├── limpar.sh                      remove o que a build criou (ver seção 7)
├── docker-compose.yml             composição: app + componentes + one-shots
├── <app>.env                      commits fixados, endereço do Kafka, caminhos (vai para o Git)
├── <app>.secrets.env.exemplo      modelo dos segredos (o .secrets.env real NÃO vai para o Git)
├── preparar-codigo.sh             clona/atualiza os repositórios nos commits do .env
├── artefatos/                     artefatos de exemplo (zonas, regras…) quando a app ainda não publicou os reais
└── aceite/                        teste de aceitação da app (opcional, recomendado)
```

**A8 é a referência:** ver a seção 5. Só falta o `limpar.sh` dele. As demais aplicações seguem o mesmo molde.

---

## 2. Contexto do projeto

- **Projeto:** ODS 2026/2. Arquitetura **6c** com quatro camadas, documentada em `ods-6cfinal.html` (Especificação de interfaces 1.0, de 13/10/2026). Peça o arquivo ao usuário se precisar de um contrato.
  - **Plataforma:** P1 imagem do sistema, P2 runtime de aceleração, P3 composição e build, P4 vídeo, P5 áudio, P6 gravação e replay, P7 pan-tilt.
  - **Inferência:** I1 detecção, I2 rastreio, I3 calibração, I4 Libras, I5 fala, I6 QR/barras, I7 placas, I8 inspeção de peças, I9 EPI.
  - **Serviços:** S1 zonas, S2 regras e eventos, S3 alertas, S4 evidência de mídia, S5 métricas, S6 síntese de Libras.
  - **Aplicações:** A1 Indústria (VER-1), A2 Acesso (VER-2), A3 Monitoramento (VER-6), A4 Esporte (INV-1), A5 EPI (VER-3), A6 Libras (APL-2), A7 Restaurante (VER-4), A8 Estacionamento (VER-5).
  - **Frentes transversais:** B1 contratos e validador (TRA-1), B2 tempo e replay (TRA-2), B3 barramento (TRA-1), B4 testes de integração (TRA-2), B5 modelos e artefatos (MOD-1), B6 interface (MOD-2).
- **Papel do P3, segundo o plano:** *"P3, pertencente ao SIS-1, define a composição, a build e o ciclo de vida por aplicação. Os squads donos fornecem componentes e artefatos versionados. O squad da aplicação seleciona versões e parâmetros. B1, B3 e B4 fornecem contratos, padrões de integração e verificação."* O P3 também empacota os serviços em container.
- **Código:** um repositório por componente em `https://github.com/ods-26-2/<id>` (`p4`, `i1`, `s5`, `a8`…), todos públicos.
  - **Branches:** a maioria só tem `main`. O S4 usa `master`, e o S2 tem a versão mais nova em `develop`.
  - **Sem CI de imagens:** as imagens são **construídas na própria Jetson**, a partir dos clones, no commit fixado.
- **Barramento:** Kafka. O Guia de Uso do Kafka (TRA-1) **proíbe broker paralelo**: toda build usa o Kafka compartilhado da turma. O repositório `b3` está vazio, e não há configuração do broker versionada.

---

## 3. A Jetson (ambiente de execução)

| Item | Valor |
|---|---|
| Máquina | Jetson Orin, usuário `ods`, hostname `ods-pc`, JetPack 6.2.1 |
| Disco | Cartão de **57 GB** (`/dev/mmcblk0p1`). **É o maior risco operacional.** |
| IP no laboratório | `172.18.4.56` |
| Kafka da turma | Container **`kafka`** (`confluentinc/cp-kafka:latest`), de **outro grupo**, com `restart: no` e **sem autenticação** |
| Listeners do Kafka | `INTERNAL localhost:9092` (só fora de containers) · **`PRIVATE 172.18.4.56:9093` (o que as builds usam)** · `EXTERNAL 200.17.66.56:9094` |
| Clone do p3 | `/opt/ods/p3` (dono `ods:docker`) |
| Código das equipes | `/opt/ods/src/<repo>` (criado pelo `preparar-codigo.sh`) |
| Dados | `/var/lib/ods/` (artefatos, vídeos, imagens do I7, mídia) |

**Onde você está rodando:** confirme com o usuário, ou com `hostname`, se o Claude Code está na Jetson (`ods-pc`) ou no computador dele. Fora da Jetson, você só edita arquivos, valida (`docker compose config`, `bash -n`, `shellcheck`) e prepara commits. Os comandos na placa ficam com o usuário, que traz a saída de volta.

**Para conferir o Kafka da turma:**

```bash
docker ps -a --filter name='^kafka$' --format '{{.Names}} {{.Status}}'
docker run --rm confluentinc/cp-kafka:latest kafka-broker-api-versions \
  --bootstrap-server 172.18.4.56:9093 2>/dev/null | grep -m1 'id:'   # deve terminar em "-> ("
```

O dono já mudou os listeners três vezes sem aviso. Se uma build parar de conectar, olhe primeiro `docker inspect kafka` (`KAFKA_ADVERTISED_LISTENERS`).

---

## 4. Regras de trabalho (não negociáveis)

**Disco**
- Antes e depois de cada build, rode `df -h /`. Abaixo de **4 GB livres**, pare.
- Depois de cada build, rode **`docker builder prune -af`**. Sem o `-a`, uns 9 GB de cache ficaram para trás.
- O disco encheu duas vezes na mesma semana. Na primeira, o Kafka da turma caiu por 4 dias.

**Comandos proibidos sem o usuário pedir explicitamente:**
- `docker system prune -a` e `docker image prune -a`: apagam imagens de serviços sob demanda (P4, I1, I7…) e as imagens base do SIS-1.
- `docker volume prune` e `docker compose down -v`: apagam bancos, clipes e o cache de modelo do I7.

**Recursos de outros grupos:** nunca pare, recrie nem reconfigure o container `kafka`, as imagens `nvcr.io/nvidia/l4t-*` e `ods/base-gpu:*` (do SIS-1) nem os containers e volumes de outras aplicações (`a1-*` etc.).

**Mínimo necessário:**
- O usuário quer **só o que a aplicação precisa**.
- Antes de compor, **leia o código da aplicação** para ver o que ela de fato consome. A árvore da 6c é o alvo, mas o código pode estar atrás dela: o A8 hoje só consome `ods.i7.plate_read`.
- Diferencie sempre "mínimo pelo código" de "cadeia do plano".

**Versões:** todo repositório fica fixado por commit completo no `<app>.env`. Nunca use `main` ou `latest` numa build.

**Segredos:** ficam só em `<app>.secrets.env`, fora do Git. O `.gitignore` do p3 já tem `builds/*/*.secrets.env`.

**Honestidade sobre validação:**
- Diga sempre o que foi validado e onde: `config` local, simulação ou execução na Jetson.
- Contornos provisórios ficam comentados no compose, com o motivo e como desfazer.

**Não editar o código das equipes.**
- Defeitos do código vão como recado para o squad dono.
- Contornos, só no compose ou no comando, e documentados.

---

## 5. Estado atual: A8 (referência, validado na Jetson)

**Arquivos em `builds/a8/`:** `a8.sh`, `limpar.sh`, `docker-compose.yml`, `a8.env`, `a8.secrets.env.exemplo`, `preparar-codigo.sh`, `artefatos/zones-a8-p3-1.json` e `.descriptor.json`, `aceite/aceite_a8.py`.

**`limpar.sh`** (13/11/2026) usa `builds/comum/lib.sh`; o `a8.sh` validado continua independente da lib.

### Builds A1–A7 e estrutura comum (13/11/2026, ainda não rodadas na Jetson)

- `builds/comum/lib.sh` (subir/status/parar/limpar), `comum/preparar-codigo.sh` (todo `<REPO>_REF` do `.env`), `comum/kafka_override/sitecustomize.py` (broker fixo no código; usado pelo A3).
- `builds/ods.sh`: `lista` e `trocar <app>` (limpa as outras com `--imagens --manter <app>` e sobe a nova).
- `builds/a1` … `builds/a7`: mesmo molde do A8; resumo por app em `builds/README.md`.
- Testes (13/11/2026): `./<app>.sh testar` (aceitação pelo Kafka, `builds/comum/aceite/` + `<app>/aceite/`), `validacao/validacao-geral/validar-sistema.sh <app>` (S1–S9) e `validacao/<app>/validar-<app>-fluxo.sh` (API). Testados só fora da placa: Kafka e APIs falsos (caminhos de falha e de sucesso).
- Validado só fora da Jetson: `bash -n`, checagem estática em Python (variáveis, commits, contextos e `COPY` no commit fixado) e os scripts contra um `docker` simulado. **Falta `docker compose config` real e a execução na placa.**

**Tags no p3:** `a8-minimo-v1` (A8 + I7). A cadeia foi validada em 12/11/2026; a tag `a8-cadeia-v1` foi proposta e precisa ser conferida com o usuário.

### Composição

| Serviço | Origem | Observação |
|---|---|---|
| `a8-mysql` | `mysql:8.4` | Schema de `a8/database.sql` aplicado na primeira subida |
| `a8-backend` | `a8/backend` | Consome `ods.i7.plate_read` (grupo `A8-acesso`); porta 3000; `/api/health` |
| `a8-frontend` | `a8/frontend` | Servidor de desenvolvimento do Expo (porta 8081); `EXPO_PUBLIC_API_URL=http://JETSON_IP:3000` |
| `i7` | `i7` | Perfil `i7`, sob demanda: lê imagens de `I7_IMAGENS_DIR` e publica placas |
| `kafka-topicos` | `cp-kafka` | One-shot: cria os tópicos da cadeia no Kafka da turma (`--if-not-exists`) |
| `p4` | `p4` + Dockerfile do P3 (`dockerfile_inline`) | Perfil `video`: toca `VIDEO_DIR/cam0.mp4` uma vez (source_id `file_cam0`) e termina |
| `i1` | `i1` (develop `cb5c381`, `Dockerfile.jetson`) | Perfil `video`; lê os quadros do P4 por SHM (`ipc: service:p4` + volume `p4-shm` em `/tmp`); **GPU/TensorRT via P2** (`ods-i1-gpu:<ref>`, `runtime: nvidia`, `P2_BACKEND=trt`). Ainda não rodado na Jetson (13/11/2026) |
| `i1-engine` | imagem do `i1` | One-shot (perfil `video`): `builds/comum/i1/preparar-engine.sh` compila a engine FP16 em `I1_ENGINES_DIR` só se ela faltar ou não carregar; o `p4` espera por ele |
| `i2` | `i2` | Contínuo; consome `ods.i1.detections` |
| `i3` | `i3` | Perfil `i3`, sob demanda (precisa de CSV de correspondências) |
| `s1` | `s1` | Contínuo; zonas de exemplo do P3 em PIXELS |
| `s4` | `s4` (target `production`) | Contínuo; lê o próprio MP4; teto de mídia de 1 GB; API em `127.0.0.1:18084` |
| `s5` | `s5` | Contínuo; API em `127.0.0.1:8000` |
| `aceite` | `aceite/` | Perfil `aceite`: o "A8 simulado" do teste de aceitação |

**De fora:** o S2, porque a `develop` lê e grava arquivos JSON e não usa Kafka.

**Uso na Jetson:**

```bash
cd /opt/ods/p3/builds/a8
./a8.sh            # confere a placa, baixa código, constrói só o que falta (em etapas, com limpeza), sobe e espera
./a8.sh testar     # A8 simulado + I7 + vídeo + pedidos ao S4/S5/S2 → resultados/aceite-a8-*.txt|json
./a8.sh status
./a8.sh parar      # down sem -v
```

**Validado na Jetson em 12/11/2026:**
- **Cadeia, por contagem no Kafka:** P4 → I1 (52 detecções) → I2 (52) → S1 (52 posições, 7 transições, 7 ocupações) → S5 (métricas).
- **APIs:** o S5 respondeu pela API com dados, e o S4 gerou um clipe pela API.
- **A8:** o I7 → Kafka → A8 decidiu `liberado (veiculo_vinculado)` e `negado (nao_cadastrado)`.
- **Script de validação da API:** `validacao/a8/validar-a8-fluxo.sh` passou.

**Ainda não rodado na Jetson:** `./a8.sh testar` e o `a8.sh` completo. Foram verificados só com Kafka simulado e `docker` falso.

### Resultado esperado do teste de aceitação hoje

| Item | Esperado | Motivo |
|---|---|---|
| C01–C08, C11–C13 | PASSOU | Cadeia e APIs funcionando |
| C14 | FALHOU | Data dos clipes do S4 ~50 h à frente (soma o uptime) |
| C18 | FALHOU | O P4 publica com o envelope do guia (`occurred_at`), sem `published_at`, `captured_at` e `sequence` |
| C09, C15 | AVISO | O I7 não lê o P4; o S4 responde em `ods.s4.clip.query.reply` (a spec diz `ods.s4.clip.reply`) |
| C10, C16, C17 | BLOQUEADO | S2 fora do Kafka; zonas em pixels, sem calibração |

---

## 6. Lições aprendidas (evite repetir)

- **`.env` do Compose:** um comentário na mesma linha de uma variável vazia **vira o valor**. Comentários sempre em linha própria.
- **Variáveis obrigatórias:** no compose, use `${VAR:?mensagem}` para a build parar com mensagem clara.
- **Kafka e containers:** o cliente usa o endereço **anunciado** pelo broker, não o configurado.
  - A porta 9092 anuncia `localhost` e falha dentro de containers.
  - Use a 9093 (PRIVATE).
  - Teste com `kafka-broker-api-versions` antes de culpar o código.
- **Contagem por tópico** (prova de cada elo): `kafka-get-offsets --bootstrap-server 172.18.4.56:9093 --topic <t>`. A função `contar` está no `~/.bashrc` da Jetson.
- **`sudo echo x >> arquivo` não funciona,** porque o redirecionamento é do shell do usuário. Use `| sudo tee -a`, ou corrija o dono com `chown -R ods:docker /opt/ods/p3`.
- **Arquivos editados à mão na Jetson** quebram o `git pull`. Compare com `git diff origin/main -- <arq>` antes de descartar com `git checkout --`.
- **`depends_on` só vale no `up`.** Depois de reiniciar a placa, o Docker religa tudo junto, e o Kafka da turma não volta sozinho.
- **Componente sem Dockerfile** (P4): use `build.dockerfile_inline` no compose, com contexto no clone.
- **Memória compartilhada P4 → I1:** volume nomeado montado em `/tmp` nos dois, mais `ipc: shareable` no P4 e `ipc: "service:p4"` no I1. O P4 recusa subir com socket velho, então o comando dele remove `/tmp/p4_file_shm` antes.
- **Contorno do I1** (`30df178`): o `run_detector.py` usa `os` e `BROKER_ENV_VAR` sem importar. O compose roda o script via `python3 -c` com os dois nomes em `builtins`. O `pyflakes` confirmou que não há outros nomes faltando.
- **O I1 sai com código 1 no fim do vídeo** ("Control socket has closed"). O `restart: on-failure:5` tenta algumas vezes; é esperado.
- **O S4 esvazia o buffer a cada `ods.session.started`.** Como lê o MP4 só na partida, reinicie o S4 depois de tocar o vídeo do P4. O `a8.sh testar` já faz isso.
- **O S5 só publica janelas com dados,** e uma vaga fica "ocupada" depois do fim do vídeo, até a próxima sessão.
- **P2 / TensorRT:** o I1 do A8 passou para a GPU em 13/11/2026 (falta rodar na placa; teste individual em `validacao/i1/testar-i1-gpu.sh`). A3/A4/A5 ainda usam o I1 antigo em CPU; o I7 continua em CPU.
  - O I1 roda `--backend ultralytics` (ONNX Runtime CPU) e instala `p2[cpu]`; o I7 usa PyTorch CPU.
  - Prova de TensorRT: `artifact_version` terminando em `-fp16`, `libnvinfer` em `/proc/1/maps` do container, `GR3D_FREQ` > 0% no `tegrastats` e `P2_BACKEND=trt`, para impedir a queda silenciosa para CPU.
- **Portas:** o Docker publica em todas as interfaces e passa por cima do `ufw`. As APIs internas (S4, S5) ficam em `127.0.0.1`. Ainda falta saber se 3000 e 8081 aparecem pelo IP público (teste com o celular em dados móveis).
- **Padrão de nomes do p3** (`image-base-v1/padronizacao/PADRAO-NOMES.md`, formato `ods/<serviço>:<versão>-jp6.2.1-b<ID>`): o usuário decidiu **manter** `ods-<serviço>:<commit>` por enquanto.

---

## 7. Como fazer a pasta de uma nova aplicação

Para cada aplicação, nesta ordem, registrando cada passo em `temp/PROGRESSO.md`:

1. **Levantar o que a aplicação consome de fato.** Clone o repositório da aplicação e procure os tópicos `ods.*`, as variáveis de ambiente (`KAFKA_*`), o banco, as portas e o Dockerfile.
2. **Comparar com a árvore da 6c** (tabela abaixo) e decidir com o usuário: só o mínimo pelo código, ou a cadeia do plano.
3. **Para cada componente:**
   - verificar se tem Dockerfile, o comando de entrada, as variáveis do Kafka, os tópicos, a entrada de dados e as portas;
   - rodar `pyflakes` ou o equivalente para pegar defeitos óbvios antes do build.
4. **Escrever os arquivos:**
   - `docker-compose.yml`, com `name: ods-<app>`;
   - `<app>.env`, com os commits completos;
   - `preparar-codigo.sh`;
   - `<app>.sh` e `limpar.sh`, a partir dos do A8;
   - artefatos de exemplo, se a aplicação ainda não publicou os reais. Marque como exemplo do P3.
5. **Validar localmente:**
   - `docker compose --env-file … config --quiet`, com clones reais;
   - `bash -n` e `shellcheck`;
   - lógica de teste contra um Kafka simulado, se houver.
6. **Na Jetson,** com o usuário: `./<app>.sh`, contagem por tópico, o fluxo da aplicação e `./<app>.sh testar`.
7. **Registrar a evidência** em `validacao/<app>/` e marcar uma tag no p3 (`<app>-minimo-v1`, `<app>-cadeia-v1`).

### `limpar.sh`: especificação (vale para todas as aplicações)

- **Padrão (sem opções):** `docker compose … --profile <todos> down --remove-orphans`. Remove os containers da build e mantém os volumes.
- **`--imagens`:** também remove as imagens da build, listadas no próprio `<app>.env` (`ods-<svc>:<REF>`), e roda `docker builder prune -af`.
- **`--dados`:** também remove os volumes da build (`docker compose down -v`). Antes, exige que o usuário **digite o nome da aplicação** para confirmar, e lembra de fazer backup do banco (ex.: `mysqldump`).
- **`--codigo`:** remove os clones que só essa build usa em `SRC_DIR`, com cuidado para não remover clones usados por outras builds.
- **Ao final:** mostra `df -h /` antes e depois.
- **Nunca toca** no container `kafka`, nas imagens do SIS-1, em recursos de outras aplicações nem na pasta `resultados/` (evidência).

### Árvore de dependências pela 6c (leitura recomendada)

P2 é biblioteca dentro das imagens de inferência, não um container. "Opcionais" são consumos marcados como opcionais no mapa.

| App | Squad | Componentes (6c) | Opcionais |
|---|---|---|---|
| A1 Indústria | VER-1 | I1 I8 P2 P4 P7 S4 S5 | S3 |
| A2 Acesso | VER-2 | I6 P4 S4 | S3 |
| A3 Monitoramento | VER-6 | I1 I2 P2 P4 S1 S2 S3 S4 S5 | — |
| A4 Esporte | INV-1 | I1 I2 I3 P2 P4 P7 S1 S4 | S5 |
| A5 EPI | VER-3 | I1 I2 I3 I9 P2 P4 S1 S2 S3 S4 | — |
| A6 Libras | APL-2 | I4 I5 P2 P4 P5 S4 S6 | — |
| A7 Restaurante | VER-4 | I5 P2 P5 S3 S5 | S4 I6 |
| A8 Estacionamento | VER-5 | I1 I2 I3 I7 P2 P4 S1 S2 S4 S5 | I6 |

**Observações para as próximas aplicações:**
- **A1 e A4 usam o mesmo P7 (pan-tilt),** sem arbitragem entre aplicações: não podem rodar juntas na mesma placa.
- **P5 (áudio)** entra em A6 e A7 e ainda não foi composto.
- **S2 está fora do Kafka,** o que bloqueia A3 e A5 nos eventos.
- **S3 nunca foi composto.**
- **Lacunas da 6c:** o S5 não tem fonte de eventos para A1 e A7, e o A4 usa o S1 sem publicar ZONES.
- **Começar pelo A2** pode ser o caminho mais curto: são só três componentes, sem GPU.
- **O A1** tem containers `a1-db-1` e `a1-kafka-1` na placa. É uma build de outro grupo, com broker paralelo; não mexa sem combinar.

---

## 8. Pendências com as equipes (atualize quando mudar)

| Equipe | Pendência |
|---|---|
| MOD-1 (I1) | Imports corrigidos e `Dockerfile.jetson` só na `develop` (`cb5c381`): fazer o merge no `main`; tratar o fechamento do socket do P4 como fim normal (código 0) |
| MOD-2 (S4) | Data dos clipes soma o uptime; tópico de resposta `ods.s4.clip.query.reply` (spec: `ods.s4.clip.reply`) |
| SIS-2 (P4) e MOD-2 (S4) | Formato da memória compartilhada (P4 manda cabeçalho `P4R1`, S4 espera quadro puro); envelope do P4 fora da 6c |
| VER-6 (S1, S2) | S2 no Kafka; S1 não "esvazia" zonas no fim da sessão |
| VER-5 (A8) | Zonas reais; consumo de S1, S4 e S5 pelo A8; I7 lendo os quadros do P4; usuário não root e frontend estático nos Dockerfiles; decisão de acesso não é gravada (só log); `baixa_confianca` (~26% das leituras) sem fluxo de conferência manual; saída usa a regra da entrada (convidado vencido fica preso); sem filtro por empresa; cancelas fixas no código |
| SIS-1 (P2) | Imagem base com TensorRT e engines compilados (`p2-build`) para I1 e I7; SSD NVMe para a placa |
| TRA-1 (B3) | Kafka da turma sem `restart`, sem autenticação, listeners mudando sem aviso, repo `b3` vazio |
| VER-1 (A1, I8) | A1 consome `ods.industria.defeito_classificado` (6c: `ods.i8.piece_analysis`); I8 sem modelo treinado no repo (a build usa os mocks 2.0 do próprio I8) |
| VER-2 (A2, I6) | Código novo só na `develop`; web-app com chave AES fixa (`b"a"*32`) e banco dentro do código; padrão `S4_CAPTURE_REPLY_TOPIC` errado (S4 responde em `ods.s4.capture.reply`); I6 espera socket TCP que o P4 não oferece |
| VER-6 (A3) | Broker fixo no código (`34.66.235.91:9093`); sem Dockerfile/requirements; código novo só na `dev` |
| INV-1 (A4) | Sem Dockerfile no back e no front |
| VER-3 (I9) | Sem Dockerfile; dataset de 323 MB no repositório |
| MOD-1 (B5) | Sem modelo de pessoas nem de EPI para o I1 (A3 e A5 usam o de placas só para provar o transporte) |
| INV-2 (I4, S6) | Repo `s6` vazio (S6 está em `i4/s6_synthesis`); I4 ao vivo depende de servidor C++ próprio |
| VER-4 (A7, I5) | Sem Dockerfile; I5 com `float16` padrão (GPU); A7 escuta `ods.s5.event.metrics` (6c: `ods.s5.event_metrics`) |
| SIS-2 (P5, P7) | Só scripts de hardware, sem Kafka: A6/A7 ficam sem P5 e A1/A4 sem P7 |

---

## 9. Referências rápidas

```bash
# Na Jetson, dentro de builds/<app>
alias dc='docker compose --env-file a8.env --env-file a8.secrets.env'   # troque a8 pela app
dc ps -a --format '{{.Name}}  {{.Status}}'
dc logs --tail 30 <serviço>
contar                         # mensagens por tópico da cadeia (função do ~/.bashrc)
ver <tópico>                   # primeira mensagem de um tópico
docker system df ; df -h /
```

**Documentos:** `ods-6cfinal.html` (Especificação 1.0 e mapa da 6c) e `Guia_Kafka_B2.pdf` (guia de uso do Kafka da turma). Os dois estão com o usuário.

**Repositórios úteis:**
- `ods-26-2/b4`: validador de contrato em `tests/integration/contract_validation.py`, usado pelo teste de aceitação.
- `ods-26-2/p2`: `docs/guia-rapido.md` explica como usar TensorRT.