# Progresso — builds ODS (P3)

## Estado atual
- Aplicação em foco: levantar todas as inferências: inf sobre a inf_a4, sem I4 e I5 (decisões de 27/11)
- Fase: compose/script alterados e validados só no notebook (bash -n, YAML, simulação do ods.sh trocar); sem commit
- Último resultado: simulação: trocar inf → limpa a1–a8 com --manter inf --manter inf_a4, sobe inf_a4 e depois inf; trocar a8 → derruba inf e inf_a4
- Próximo passo: commit (aguarda usuário); na placa: git pull, ../i1/i1.sh parar, docker tag do I2 (5283d60→5f4957c) e do I3 (c3d876e→0a7f944), df -h /, ./ods.sh trocar inf (reconstrói o I6), ./inf.sh testar
- Bloqueios / perguntas abertas ao usuário: enviar recados SIS-2 e VER-4; recado MOD-1 adiado; teste do P4 (.txt, --desfazer); A2 sem commit; disco ~4 GB
- Continuidade: journal.md (raiz) = retrato do projeto, atualizar a cada pedido; este arquivo e o CLAUDE.md versionados a pedido do usuário (13/11/2026); temp/ segue no .gitignore (PROGRESSO.md entrou com git add -f).

## Registro

> Entradas de 13/11 a 18/11/2026 arquivadas em [PROGRESSO-arquivo-2026-11-27.md](PROGRESSO-arquivo-2026-11-27.md).

### 2026-11-23 — pedido: build dedicada ao I1 (sempre pronto na Jetson) + guia de teste
- Pedido do usuário: ler o feito (sobretudo A8), preparar build especial só do I1, analisar as mudanças novas do repo, guia de teste. Será usada junto com uma futura build "todas as inferências do plano".
- Máquina: "argenti" (computador do usuário, não a Jetson): só edição e validação local.
- I1 develop andou: cb5c381 → 3b2a9cc (20/11, girafinos). Novo: I1/detector/orchestrator.py + I1/run_orchestrator.py (daemon FIFO que escuta ods.i1.command; START/STOP/HEARTBEAT; 1 modelo por vez no P2, release antes do load; TTL padrão 60 s sem heartbeat; force=true preempta), serviço i1-orchestrator no compose do I1 (ipc host, network host, /tmp:/tmp), tests/test_orchestrator.py. Dockerfile.jetson e pipeline/ingestão NÃO mudaram.
- Perfis fixos no código: INV1/A4 app-sports-1.2.0 (1280, ball), VER1/A1 app-industry-1.0.0 (peca), VER3/A5 app-epi-1.0.0, VER5/A8 app-plates-1.0.0, VER6/A3 app-epi-1.0.0 (só pessoa). Vídeo por equipe em I1_VIDEOS_DIR (<SQUAD>.mp4 etc.) ou "source" explícito (caminho, video/imx519/imx477 = SHM do P4). source_id padrão = nome da equipe.
- Atenção: broker padrão do orquestrador = 34.66.235.91:9093 (nuvem; doc diz "apps na nuvem, inferência na Jetson") — conflita com o Kafka da Jetson do CLAUDE.md: perguntar ao usuário. Consumer group com auto commit: comandos enviados com o I1 parado são reprocessados na volta.
- Validado aqui: unittest tests.test_orchestrator 6/6 OK (venv no scratchpad); pyflakes só imports não usados.
- Próximo: escrever builds/i1/ (compose name ods-i1, i1.env, i1.sh, limpar.sh, preparar-codigo.sh, engines de todos os pacotes) e o guia validacao/i1/GUIA-BUILD-I1.md; conferir ods.sh/lib.sh para a build do I1 não ser derrubada no "trocar".
- Decisões de desenho (builds/i1, projeto ods-i1):
  - Serviço i1 = run_orchestrator.py do 3b2a9cc, imagem ods-i1-gpu:<ref> (Dockerfile.jetson + l4t-tensorrt, igual A8/A5), restart unless-stopped, logs com rotação (10m x 3), broker da Jetson por ODS_KAFKA_BROKER (padrão do código é a nuvem).
  - Vídeos: VIDEO_DIR montado em /videos (I1_VIDEOS_DIR=/videos): <SQUAD>.mp4 ou "source" explícito no comando.
  - SHM do P4 de outra build: ipc host + pasta do host I1_P4_DIR (/var/lib/ods/p4-shm) montada em /tmp (a build de inferências faz o mesmo no P4). /tmp do host não serve: some no boot e o bind falharia.
  - i1-engine (perfil engine) compila/confere TODOS os pacotes de I1_PACOTES; i1.sh roda depois do up (o daemon só carrega engine quando chega START).
  - kafka-topicos cria ods.i1.command e ods.i1.detections.
  - Teste: serviço aceite com a própria imagem do I1 (confluent-kafka + jsonschema + schema do I1, sem build extra) + ods_aceite.py; i1.sh entrega o log do i1 ao teste (passo "log") para conferir motivos de encerramento.
  - lib.sh: imagens das builds permanentes (i1) protegidas no limpar --imagens das apps; ods.sh lista mostra o i1. apps() já ignora i1 no trocar.
- 2026-11-23 escritos: builds/i1/{i1.env,docker-compose.yml,i1.sh,limpar.sh,preparar-codigo.sh,aceite/aceite_i1.py}; comum/lib.sh (ODS_PERMANENTES=(i1): imagens do i1 protegidas no limpar --imagens de outras builds); ods.sh (lista mostra i1; trocar não mexe). bash -n ok; pyflakes do aceite ok.
- Próximo: validar compose (pyyaml + interpolação), simular o aceite contra orquestrador real em modo mock (venv) e Kafka falso; escrever validacao/i1/GUIA-BUILD-I1.md.
- 2026-11-23 simulação (scratchpad/sim-i1/rodar.sh): orquestrador REAL do 3b2a9cc + p2 falso (engine_version <ref>-fp16) + Kafka falso em arquivo + aceite_i1.py + validador B4 bb2ea8c. Cenário ok: PASSOU 15, AVISO 2 (VER1/INV1 sem vídeo próprio), código 0. Cenário sem engine do sports: T1-INV1 e T40 FALHOU (esperado). Corrigido: T22b contava o JSON quebrado que o próprio teste manda; caminhos do teste configuráveis por env. awk do "ocupado" conferido no log real.
- Próximo: validacao/i1/GUIA-BUILD-I1.md, README de validacao/i1, builds/README.md, CLAUDE.md (seções 5 e 8).
- 2026-11-23 docker/git falsos (scratchpad/sim-sh, cópia de builds/): i1.sh subir (sem imagem: build i1 → prune → up → i1-engine → espera "Aguardando comandos"), testar (aceite, log entregue, limpeza de .passo/.i1-log), status, comando (run --rm --no-deps aceite com --send-command) ok; a8/limpar.sh --imagens mostra "mantida (o i1 usa)"; i1/limpar.sh --imagens remove a própria. Corrigido: comando cria resultados/ antes do run.
- Escrito validacao/i1/GUIA-BUILD-I1.md (passos, itens esperados, resiliência R1–R3, contrato para outras builds, validação feita, pontos em aberto).

### 2026-11-23 — respostas do usuário: nuvem, A8/A5 no I1 novo, vídeos em assets/, commit
- Usuário: aplicações migraram para a nuvem; na Jetson rodam as inferências (I's). → broker do I1 = nuvem 34.66.235.91:9093 (padrão do orquestrador). Checagem do container "kafka" local deixa de valer para o I1 (lib: KAFKA_CONTAINER vazio pula).
- A8 e A5: I1_REF → 3b2a9cc (não serão rodados agora). Foco: testar o I1.
- Vídeos: assets/ na raiz do p3 (INV1.mp4, VER1.mp4, epi.mp4; 53 MB) → versionar e ./i1.sh videos copia para VIDEO_DIR com os nomes do orquestrador (VER3/VER6 → epi.mp4, VER5 → cam0.mp4 se existir).
- Commit pedido (só I1 + A8/A5 + assets + docs; A2 continua fora). Usuário faz pull depois.
- Feito (23/11): a8.env/a5.env I1_REF 3b2a9cc; lib.sh checar_kafka com KAFKA_CONTAINER (vazio = broker remoto; testado com docker falso nos 3 casos); i1.env KAFKA_BROKER nuvem, I1_VIDEOS (substitui I1_TESTE_VIDEOS); i1.sh videos (copia assets/ → VIDEO_DIR, links <SQUAD>.mp4; testado 2× numa cópia) e status com vídeos; guia e CLAUDE.md atualizados.
- Vídeos (ffprobe): INV1 1920x1080 29,97 fps 963 quadros; VER1 3840x2160 29,97 fps 255 quadros; epi 1920x1080 24 fps 192 quadros; todos H.264.
- Broker da nuvem: list_topics a partir do computador do usuário → Connection refused na 9093.
- Commit (só I1, A8/A5 env, lib, ods.sh, assets, docs; A2 fora). Sem push.

### 2026-11-23 — Kafka da nuvem não responde (Jetson e computador do usuário)
- Jetson: kafka-broker-api-versions em 34.66.235.91:9093 sem saída. Daqui: 9092/9093/9094/29092/19092 recusadas (RST: a máquina responde, nada escutando).
- Repos da turma (s4 DEMO/PLANO, a7, i4, a2) confirmam 34.66.235.91:9093 como broker da TRA-1 no GCP; i4/z_script.sh: "não deixe nada rodando: gasta crédito do GCP" → broker provavelmente só ligado sob demanda.
- Próximo: usuário pede à TRA-1 para ligar o broker (ou decide testar o I1 no Kafka da placa, trocando KAFKA_BROKER/KAFKA_CONTAINER).
- Notebook do usuário: /dev/tcp 34.66.235.91:9093 → Connection refused (confirma). Usuário: esse Kafka não está na Jetson (é o do GCP/TRA-1).

### 2026-11-23 — decisão: testar o I1 no Kafka da placa
- Usuário: seguir com o teste no Kafka local. Feito: suporte genérico a <app>.local.env (fora do Git) na lib (source depois do <app>.env e --env-file por último no dc) + builds/i1/i1.local.env.exemplo (172.18.4.56:9093, KAFKA_CONTAINER=kafka).
- Testado com docker falso: sem local.env → erro com dica do i1.local.env; com local.env → checa container kafka e compose recebe --env-file i1.local.env por último.

### 2026-11-23 — Jetson: git pull barrado por temp/PROGRESSO.md alterado na placa; A8 de pé com s4/s5 'Created' (127.0.0.1:8000 já ocupado)
- Orientação: guardar cópia do PROGRESSO da placa, git checkout -- temp/PROGRESSO.md, pull; ver quem ocupa a 8000; parar o A8 antes do teste do I1 (I2 do A8 consome ods.i1.detections no Kafka da placa).

### 2026-11-23 — Jetson: ./i1.sh parou no checar_disco (2 GB livres; mínimo 4 + ~2,5 da imagem nova)
- Orientação: diagnóstico (docker system df, imagens por tamanho, ods.sh lista, du de /var/lib/ods) e passos seguros: builder prune -af; ods-i1-gpu:cb5c381 obsoleta (A8/A5 agora em 3b2a9cc) sai depois do ./a8.sh parar. Remover imagens de apps só com decisão do usuário.
- Observação: a dica da lib '../ods.sh trocar i1' não serve bem para build permanente (corrigir depois).
- Saída da Jetson: 2,0 GB livres; ods-i1-gpu:3b2a9cc JÁ EXISTE (não precisa construir); ods-i1-gpu:cb5c381 obsoleta; ods-i1:30df178 (CPU, só A3/A4, nunca rodados na placa); ods-i5-gpu/ods-i5/ods-aceite-i5 d7b1379 não vêm de nenhum .env do repo (trabalho feito na placa? perguntar); volumes 1,6 GB reclamáveis (não mexer). Recomendado: rmi cb5c381 + 30df178 e conferir df.

### 2026-11-23 — 1º ./i1.sh na Jetson (Kafka da placa via i1.local.env): I1 PRONTO
- Disco: ods-i1:30df178 removida (2,0 → 4,8 GB); fim da subida com 7 GB livres (cb5c381 removida também, presumivelmente).
- Imagem ods-i1-gpu:3b2a9cc já existia (sem build). drop_caches: 363 → 2858 MB livres.
- Engines: plates e epi conferidas; industry compilada sem erro; sports (1280) compilada, mas o TensorRT pulou 3 táticas por falta de memória da GPU (pedia 485 MB; NvMap error 12) → engine válida (passou na entrada zerada), possivelmente não a mais rápida. Recompilar com mais memória livre se o desempenho do INV1 ficar ruim.
- Orquestrador: "Aguardando comandos em 'ods.i1.command' (broker='172.18.4.56:9093', backend='p2', mode='kafka', videos_dir='/videos')".
- Próximo: ./i1.sh status, pedido manual VER5, ./i1.sh testar.

### 2026-11-23 — pergunta: ./i1.sh testar roda os testes do repo do I1? Não.
- testar-i1-servico.sh passa a aceitar --build i1|a8 (padrão i1): lê i1.env (+ i1.local.env), sem segredos/perfil; o bind de I1_P4_DIR em /tmp fica fora do teste. S03 continua em stdout (run_detector só lê o broker do ambiente).
- Suíte do 3b2a9cc fora da placa (venv): 46 testes, só test_05 com erro (ultralytics) → S02 deve passar com 45/46.

### 2026-11-24 — Jetson: ./i1.sh testar PASSOU 16, FALHOU 0, AVISO 1
- Kafka da placa (i1.local.env). Troca de modelo 0,2–0,8 s; START→1ª msg 5,2–12,1 s (fila de 5); ~25 q/s no cam0; T33 = vídeo cam0 inteiro (270 quadros; T31–T33 usam o vídeo do VER5); B4 150 válidas; RestartCount 0→0; sem OOM.
- AVISO T1-INV1 (app-sports, classe única "ball"): ONNX original na CPU (scratchpad/tools/bola.py) também não vê bola nos quadros 0–29 do INV1.mp4 (máx. 0,063); aparece a partir do ~120 (12/32 amostras >= 0,5). Conclusão: vídeo, não a engine com táticas puladas.
- Arquivos: aceite_i1.py (I1_TESTE_QUADROS_EQUIPE), docker-compose.yml (repassa), i1.env (INV1=150), evidencias/aceite-i1-20261124-011649.txt, GUIA (estado, tabela, seção 9), CLAUDE.md seção 5. Validado: py_compile, YAML, source do .env. Sem commit.

### 2026-11-24 10:19 — Jetson: R1 (kill -9 no processo do I1)
- RestartCount 0 → 1, running, "Aguardando comandos" de novo (broker 172.18.4.56:9093).
- Pedido VER5 teste-r1 entregue, mas sem "Carregando app-plates"/"VER5 encerrada" nos 20 s seguintes. Hipótese: após kill -9 o membro morto segura a partição do grupo até o session.timeout do librdkafka (45 s); o pedido deve ter sido atendido depois. Pedido ao usuário: docker logs --since 5m | grep VER5.
- Linhas VER3 p3-teste-heartbeat de 10:19:33 no log: provavelmente o ./i1.sh testar rodado de novo de manhã (confirmar com ls resultados/); se não foi, é replay de comando antigo.
- Pergunta do usuário: URL/porta do I1? Resposta: não tem; só Kafka (ods.i1.command / ods.i1.detections).

### 2026-11-24 — pedido: builds das inferências e build única "inf"
- Usuário: analisar o código dos repositórios I e montar os builds deles, com alvo final um único build "inf" que sobe todas as inferências.
- Decisão anterior (CLAUDE.md): a build de todas as inferências NÃO tem i1 próprio; pede ao orquestrador de builds/i1 por ods.i1.command.
- Ambiente local: docker sem compose plugin e sem acesso ao socket; sem shellcheck/pyflakes. Validação local fica em bash -n + checagem Python.
- Próximo: levantamento i2..i9 (Dockerfile, entrada, tópicos, broker, dados de entrada, GPU).

### 2026-11-24 — levantamento dos repositórios I (clones em scratchpad/src)
- I1 develop 3b2a9cc (= builds/i1): orquestrador lê arquivo (VIDEO_DIR/<SQUAD>.mp4) ou socket do P4 (/tmp/p4_*_shm). A inf NÃO tem i1: pede por ods.i1.command.
- I2 main 5283d60 (sem mudança): Dockerfile; --i1/--kafka/--fps; contínuo.
- I3 main c3d876e (novo; builds usam ac28d37): --kafka agora EXIGE --registro (6c ciclo de vida); calibração sem clique pela quadra do A4 (dados/quadra_mediana.png + padroes/quadra-volei-fivb.json) → one-shot autocontido.
- I4 main 503f64b (novo; A6 usa 61b39a1): compose próprio com server C++ (dockerfile.server, websocket 18080, grava /dev/shm/frames_cam) + i4 ao vivo (dockerfile.python, REQS=requirements-i4.txt, mediapipe+torch CPU, ipc service:server) + s6. webcam.py só aceita índice de câmera → P3 precisa de um enviador de vídeo (teste.mp4 do repo) por websocket.
- I5 main d7b1379 (novo; A7 usa cdb00d2): agora tem Dockerfile/Dockerfile.jetson (Jetson usa l4t-pytorch r35 = JetPack 5, incompatível com JP 6.2.1). Modo produção: --kafka consome ods.p5.audio_chunk (broker só pelo YAML) + mock_p5_producer.py (arquivo → audio_chunk). Sem --wake-word = modo contínuo.
- I6 main 86ae5d7 (= A2): modo teste lê arquivo em laço; nenhum vídeo com QR em lugar nenhum → P3 gera um com cv2.QRCodeEncoder (opencv-contrib da própria imagem).
- I7 main 1441bbb (novo; A8 usa a4da4b0): Dockerfile com P2 CPU (p2-build no build, DETECTOR=p2), --video nativo (substitui o extrair_quadros do P3), --p4 video|imx519.
- I8 main 051851f (= A1): sem modelo; publisher dos mocks 2.0 com taxonomia do A1 (precisa do clone do a1).
- I9 main 8ae3933 (= A5): sem Dockerfile (P3 inline); catálogo opcional (política padrão).
- Desenho: builds/inf (projeto ods-inf), um compose com seção por I, scripts de apoio em inf/<iX>/; contínuos: i2, i4-server, i4, i5, i6, i9; sob demanda: i3, i4-video, i5-audio, i7, i8; I1 externo (builds/i1).

### 2026-11-24 — build inf: arquivos (1ª parte)
- Criados: builds/inf/inf.env, docker-compose.yml (kafka-topicos, i2, i3, i4-server, i4, i4-video, i5, i5-audio, i6, i6-gerar-video, i7, i8, i9), i4/enviar_video.py, i6/gerar_video_qr.py, i5/pipeline_config.yaml (broker __KAFKA_BROKER__ trocado na partida).
- Movido: builds/a1/i8 → builds/comum/i8 (git mv); a1/docker-compose.yml monta ../comum/i8.
- Imagem do I5 com nome ods-i5-cpu:<ref> para não colidir com ods-i5:d7b1379 que já existe na placa (origem desconhecida).
- Próximo: inf.sh, limpar.sh, preparar-codigo.sh, inf.local.env.exemplo, ods.sh (inf trocável), testar.

### 2026-11-24 — build inf completa (validada só fora da Jetson)
- Arquivos: builds/inf/{inf.sh, limpar.sh, preparar-codigo.sh, inf.local.env.exemplo}; ods.sh (apps() inclui inf; cabeçalho); builds/README.md (seção inf); validacao/inf/GUIA-BUILD-INF.md; CLAUDE.md (seção 5 e pendências INV-2/VER-4); comum/preparar-codigo.sh passa a ler o <app>.local.env (antes ignorava um SRC_DIR local).
- Validação local: docker compose v2.32.4 e shellcheck 0.10 baixados em scratchpad/bin. config --quiet OK com clones reais; caminhos de COPY/volumes conferidos nos commits; shellcheck só SC2034 (variáveis da lib); py_compile dos scripts do P3.
- Simulação (docker falso em scratchpad/sim): subir (etapas de build na ordem; gera vídeo de QR), testar sucesso (PASSOU 10) e falha (I7 código 3, I5 sem transcrição → FALHOU 2, rc 1), broker diferente do I1 → recusa, i1 com quadros inválidos → erro, contar, status, limpar --imagens, ods.sh lista (inf aparece).
- Sem commit.
- Próximo: usuário decide o commit; na Jetson: git pull; builds/i1/i1.sh status; cd builds/inf; (cp inf.local.env.exemplo inf.local.env se o I1 estiver no Kafka da placa); ./inf.sh; ./inf.sh testar.

### 2026-11-24 — commits
- 9eb1ea4 (I1: aceite 16/0/1 e INV1=150) e 73564ba (build inf). A2 fora (segue sem commit). Sem push.

### 2026-11-24 — Jetson: ./ods.sh trocar inf em andamento (construindo; ~7,9 GB livres)
- Containers fora do p3: ods-i5-kafka-topicos-1 (projeto ods-i5, 4 dias, origem desconhecida, mesmo das imagens ods-i5*:d7b1379); a8-mysql (projeto "a8", compose da própria VER-5, anterior à nossa build; volume a8_mysql_data 197 MB). Não mexer sem os donos; candidatos se o disco apertar.
- Imagens da placa no containerd (/var/lib/containerd). docker system df -v falha durante build (corrida com o apt); usar df -h /.

### 2026-11-24 — Jetson: DISCO CHEIO no build da inf ("no space left on device" ao gravar o metadata do compose build)
- Começou com ~7,9 GB livres. checar_disco só roda entre etapas; uma etapa (provável imagem com torch) passou do limite. Hipótese: containerd snapshotter guarda blobs comprimidos + camadas descompactadas (~2x).
- Orientação: conferir Kafka da turma; docker builder prune -af; ver etapa no ~/build-inf.log; não usar system/image prune -a.
- Imagens após a falha: todas da inf construídas MENOS ods-i7:1441bbb (a última etapa). ods-i5-cpu 3,16 GB, ods-i4 2,55, ods-i4-server 1,42, ods-i1-gpu 6,08.
- Fora do p3 (projeto ods-i5, origem desconhecida, nomes no padrão do p3: ods-aceite-i5:1): ods-i5:d7b1379 3,17 GB + ods-i5-gpu:d7b1379 5,99 GB + ods-aceite-i5:1 0,3 GB = ~9,5 GB. Pedido ao usuário: de quem é (working_dir do ods-i5-kafka-topicos-1).
- O grep do build-inf.log não acha "Construindo": o cabeçalho da etapa vai só para o terminal (a lib faz tee só da saída do build).

### 2026-11-24 — decisão do usuário: I7 da inf na GPU (P3, base l4t-tensorrt como o I1, P2 trt, sem torch)
- Próximo: conferir API do P2 0.1.0 (I7) x 0.2.0a1 (I1), deps do fast-alpr, receita do Dockerfile.jetson do I1.
- Feito: builds/inf i7 → imagem do P3 ods-i7-gpu (dockerfile_inline, base TRT_BASE_IMAGE = l4t-tensorrt r10.3.0, P2 0.2.0a1 [trt], sem torch/ultralytics; opencv-headless 4.11.0.86 e onnxruntime 1.23.2 fixados por causa de numpy<2 e cp310 aarch64), runtime nvidia, engine ENGINES_DIR/app-plates-1.0.0 do I1 em :ro (mesmo ONNX, sha256 b698a519…; metadata idêntico; API do P2 0.1.0→0.2.0a1 compatível com detector_p2.py).
- inf.sh: checar_gpu_i7 (runtime nvidia + engine), aviso no subir; no testar o I7 roda depois do I1/I9 e o T-I7 exige artifact_version -fp16 (prova de TensorRT).
- Validado fora da placa: compose config (v2.32.4), shellcheck, simulação (GPU ok → PASSOU; fp32 → FALHOU; sem nvidia → FALHOU sem abortar; ./inf.sh i7 sem engine → erro com dica).
- Observação: P2 v0.2.0a3 já traz Whisper (whisper_setup) → possível caminho para o I5 na GPU depois.
- Próximo: commit; na placa: liberar disco (ods-i5* de origem desconhecida, ~9,5 GB, após confirmar dono), git pull, ./inf.sh subir (constrói só o ods-i7-gpu), ./inf.sh testar.

### 2026-11-24 — decisão do usuário: I5 fora da build inf (comentado) e manter só a imagem I5 mais recente
- Imagens na placa (lista do usuário): ods-i5-cpu 24/11 (nossa), ods-i5-gpu 20/11, ods-aceite-i5:1 19/11, ods-i5 19/11. O usuário chama de "meu i5" a build própria dele (projeto ods-i5); "mais recente" = ods-i5-gpu (confirmado pelo usuário).
- Feito: compose com i5, i5-audio e volume i5-cache comentados (cabeçalho explica como voltar); inf.sh sem i5 em ETAPAS, aceite_conferir, disparo e comando (erro claro); T-I5 vira AVISO "fora da build". GUIA, README, CLAUDE.md atualizados.
- Validado: compose config (serviços kafka-topicos i2 i4-server i4 i6 i9), shellcheck, simulação PASSOU 9 / AVISO 1 (T-I5).
- Placa: remover ods-i5-cpu (não usada), ods-i5:d7b1379 e ods-aceite-i5:1 (mais antigas); manter ods-i5-gpu.
- Confirmado pelo usuário: das imagens de I5 fica só a ods-i5-gpu:d7b1379 (saem ods-i5-cpu, ods-i5:d7b1379 e ods-aceite-i5:1).
- Commit pedido pelo usuário (I7 GPU + I5 fora).

### 2026-11-24 — pedido: script que roda as suítes das equipes nas imagens da inf (validacao/inf/testar-inf-repos.sh)
- Feito: validacao/inf/testar-inf-repos.sh (R-I1 via testar-i1-servico.sh; R-I2/R-I3 testes já na imagem, I3 com dados/ por volume; R-I4 tests/ por volume + pytest instalado na hora; R-I8 CMD da imagem do publicador; R-I9 tests/ por volume; I6/I7 sem suíte = AVISO). Imagens lidas do docker compose config da inf; --network none (menos I4). Relatório em validacao/inf/resultados/.
- Validado: bash -n, shellcheck, simulação com docker falso (unittest e pytest, sucesso e falha; extração dos testes com problema corrigida). I9 local: 130 testes OK (Python 3.10). GUIA seção 4.
- Próximo: commit; na placa: ./testar-inf-repos.sh (depois do ./inf.sh subir).
- Commit do testar-inf-repos.sh pedido pelo usuário.

### 2026-11-24 22:28 — Jetson: 1ª execução do testar-inf-repos.sh
- R-I1 PASSOU (45/46, CMD -fp16), R-I8 PASSOU (139), R-I9 PASSOU (130), R-I6/R-I7 AVISO.
- R-I2/R-I3 FALHOU: .dockerignore das equipes tira I2/tests e I3/tests (e dados/ do I3) da imagem → erro meu (afirmei que estavam na imagem). Corrigido: testes do clone por volume.
- R-I4: 74 passed, 3 failed (parquet: pandas não acha pyarrow na imagem, embora o requirements-i4 peça pyarrow>=15; existe roda cp311 aarch64). Não afeta o ao vivo. Diagnóstico pedido ao usuário (pip show / import pyarrow).
- Script: clone_no_commit (item FALHA se o clone de SRC_DIR não está no <REPO>_REF do inf.env). testar-i1-servico.sh: título dizia "build do A8" sempre → usa $NOME_BUILD.
- Evidência: validacao/inf/evidencias/inf-repos-20261124-2228.txt. Validado: shellcheck, simulação (inclusive clone fora do commit).
- Diagnóstico I4 (Jetson): pyarrow 26.0.1 instalado; import falha "requires NumPy 2.0 or newer, found 1.26.4". Causa: requirements-i4 numpy<2 + pyarrow>=15 sem teto (pyarrow não declara numpy, o pip não acusa). Pendência INV-2 (sugestão: pyarrow==17.0.0, como o S6 do A6). Sem contorno na build: o ao vivo não usa parquet.
- Commit pedido pelo usuário (correção I2/I3, clone_no_commit, evidência, pyarrow).
- Jetson (2ª execução, i2 i3, script b879079): R-I2 35 OK, R-I3 33 OK. Placar das suítes: PASSOU 5 (I1 I2 I3 I8 I9), FALHOU 1 (I4 pyarrow), AVISO 2 (I6 I7). Evidência e guia atualizados (sem commit).
- Jetson: ods-i7-gpu:1441bbb construída em 24/11 21:56, 1,86 GB (tamanho lógico; camadas da base l4t-tensorrt divididas com o ods-i1-gpu). Disco: 6,4 GB livres (89%). Próximo: ./inf.sh status e ./inf.sh testar.

### 2026-11-25 — Jetson: ./inf.sh testar travou no I3
- Causa: rodar() usa "docker compose run -T"; o stdin continua ligado ao terminal, mas não é TTY; o I3 com --linhas faz sys.stdin.read() quando stdin não é TTY (run_calibracao.py:115) e espera EOF para sempre. O HOW_TO_RUN do I3 usa < /dev/null.
- Correção: rodar() com < /dev/null (todos os disparos). shellcheck ok. Simulação não pegava (docker falso não lê stdin).
- Na placa: docker rm -f ods-inf-i3-run-117239d82196; depois do commit/pull, ./inf.sh testar de novo.
- Commit pedido pelo usuário (rodar com < /dev/null + evidência/guia da 2ª execução das suítes).

### 2026-11-25 10:31 — Jetson: Kafka da nuvem (34.66.235.91:9093) de dentro da rede ods-inf_default
- kafka-broker-api-versions: "Bootstrap broker ... disconnected"; kafka-topics --list: "Connection to node -1 could not be established" em laço. Mesmo quadro de 23/11. Causa a distinguir: broker desligado (recusa), firewall (tempo esgotado) ou listener com TLS/SASL (porta abre e o broker derruba).
- Mantém o Kafka da placa (i1.local.env / inf.local.env). Pedido ao usuário: teste TCP puro da placa e do notebook; perguntar à TRA-1 se o broker está ligado e como é o listener.
- Notebook do usuário (25/11): /dev/tcp 34.66.235.91:9093 → Connection refused (RST imediato: a máquina responde e nada escuta na porta; firewall do GCP costuma descartar em silêncio). Conclusão provável: broker da nuvem desligado. Troca só depois de a TRA-1 ligar.

### 2026-11-25 07:25 — Jetson: 1º ./inf.sh testar completo (Kafka da placa)
- PASSOU 8 (I1, I1M, I2, I3, I4 sign+1, I6 28, I8 +4, I9 150), AVISO 1 (I5 fora), FALHOU 1: T-I7 código 139 = SIGSEGV na imagem ods-i7-gpu (P3).
- Evidência: validacao/inf/evidencias/aceite-inf-20261125-072508.txt.
- Próximo: diagnosticar o segfault do I7 (import cv2/numpy, p2.load da engine, fast_alpr, script completo com saída).
- Diagnóstico I7 (Jetson, 25/11 11:01): numpy 1.26.4 / cv2 4.11.0 ok; p2.load → app-plates-1.0.0-fp16 (TensorRT na GPU) ok; fast_alpr ok (aviso inofensivo do onnxruntime "GPU device discovery failed"); I7 completo: 20 quadros, 20 com placa (OVK7900, ODI9001, ODA4357, PPY1001), 4 eventos entregues em ods.i7.plate_read, versão -fp16. O OCR foi baixado nesta execução (cache vazio) → no testar o I7 caiu ANTES de baixar o OCR e de publicar (plate_read 341→341). Falha intermitente/de contexto. Pedido: código de saída desta execução, dmesg (segfault/NvMap) da hora do testar, repetir ./inf.sh i7 e ./inf.sh testar.

### 2026-11-25 08:05 — Jetson: 2º ./inf.sh testar: PASSOU 9, FALHOU 0, AVISO 1 (T-I5)
- I7 na GPU: 4 leituras (-fp16). A queda 139 do 1º teste não se repetiu (OCR já no cache; dmesg sem registro).
- Observação: I4 publica sign sem keypoints/facial_marker.
- Evidência: validacao/inf/evidencias/aceite-inf-20261125-080428.txt. CLAUDE.md (seção inf) e GUIA atualizados. Sem commit.
- Próximo: commit; propor tag inf-v1 (CLAUDE §7.7); troca para o Kafka da nuvem quando a TRA-1 ligar.
- Jetson 25/11 (11:10 nos logs do container): ./inf.sh i7 sozinho → código 0, 4 eventos, OCR do cache (sem download). O dmesg não rodou (erro de sintaxe na colagem: comentário junto do comando).
- dmesg (segfault|nvmap) vazio: nenhum registro do kernel. Queda 139 do 1º teste fica como ocorrência única sem causa (o anel do dmesg pode ter girado; se voltar, coletar dmesg e docker logs na hora).

### 2026-11-25 — Balanço "está tudo de pé?"
- Feito: GUIA-BUILD-INF.md corrigido (linha "nenhuma imagem construída na Jetson" estava velha; testar sem I5).
- Resultado: inf validada só com o Kafka da placa; nuvem, I5, A1–A7 na placa e keypoints do I4 seguem em aberto.
- Próximo: commit das evidências/docs + tag inf-v1 (aguarda o usuário).

### 2026-11-25 — A8 reconstruída na placa (~2 h) e imagens salvas no PC
- Feito: `./ods.sh trocar a8` levou quase 2 h (build do zero). As 11 imagens da A8 (sem cp-kafka e ods-i1-gpu)
  foram salvas no PC do usuário por `ssh … docker save | zstd`: ~/ods-imagens/a8-20261125.tar.zst (2,2 GB),
  lista + a8.env em a8-20261125.lista.txt. Conferido: tar íntegro, 11 tags no manifest.json = lista.
- Restaurar: `zstd -dc … | ssh ods@172.18.4.56 'docker load'` (≈2,4 GB na placa) e `./a8.sh`.
- Próximo: resultado do ./a8.sh testar (não informado); oferta de `ods.sh guardar/restaurar <app>`.

### 2026-11-25 — pedido: build "inf_restrita" (I1, I2, I3), conteúdo mais novo, Kafka local sempre
- Levantamento (ls-remote/clones no scratchpad): I1 develop 3b2a9cc (20/11, mais nova que todas as feat/*), I2 main 5283d60, I3 main c3d876e: iguais aos da inf/i1.
- Arquitetura: I1 <- P2 (wheel 0.2.0a1 no Dockerfile.jetson), B5 (pacotes em I1/artifacts; B5 main 04/11 só tem app-plates/app-epi, mesmo sha do plates), P4 (opcional: SHM; o orquestrador lê vídeo). I2 <- ods.i1.detections. I3 <- dados/ do clone; publica calibration + artifact.published. B4 só para validação.
- Decisão (minha, a confirmar): I1 PRÓPRIO na build (mesma imagem ods-i1-gpu:<I1_REF> do builds/i1, não reconstrói), KAFKA_BROKER=172.18.4.56:9093 no .env (o builds/i1 fica para a nuvem). Se o I1 permanente estiver no MESMO broker, a subida recusa (dois orquestradores na GPU).
- Ambiente local: python3 do asdf sem versão nesta pasta; usar /usr/bin/python3.
- Feito: builds/inf_restrita/{docker-compose.yml, inf_restrita.env, inf_restrita.sh, limpar.sh, preparar-codigo.sh, contrato/validar.py}; validacao/inf_restrita/GUIA-BUILD-INF-RESTRITA.md; testar-inf-repos.sh ganhou --build inf|inf_restrita (resultados em validacao/<build>/resultados); testar-i1-servico.sh aceita --build inf_restrita (e lê <build>.local.env); ods.sh lista inf_restrita; builds/README.md e CLAUDE.md §5.
- Validação local: docker-compose v2.32.4 e shellcheck 0.10.0 copiados do scratchpad de 24/11 para o desta sessão. Defeito achado e corrigido antes da simulação: contrato() com pipefail somava uma 2ª linha "CONTRATO 0 0" quando o validador saía com 1.
- Simulação (docker falso em scratchpad/sim): testar sucesso PASSOU 10; I2 inválido + I1 fp32 → T-C2 e T-I1G FALHOU; I1 sem resposta + I3 código 2 → 7 FALHOU após 5 min; subir encadeia (videos via ../i1/i1.sh videos, engines, "Aguardando comandos"); repos chama testar-i1-servico.sh --build inf_restrita; repos i4 recusado; inf padrão inalterada.
- Commits pedidos pelo usuário: 771a237 (inf: evidência 25/11 + guia) e 7ea744f (inf_restrita). Sem push. A2 segue sem commit.

### 2026-11-25 19:xx — Jetson: inf_restrita de pé e testada (Kafka da placa)
- ./inf_restrita.sh status: i1 e i2 running, 0 reinícios; sessão INV1 encerrada (max_frames_reached, 150 quadros); último teste resultados/aceite-inf_restrita-20261125-161228.txt: PASSOU 10, FALHOU 0, AVISO 0. I1 permanente não aparece de pé.
- Disco: 3,7 GB livres (94%), ABAIXO do mínimo de 4 GB: próxima build vai parar (checar_disco).
- Pergunta do usuário: a build considera o Kafka da nuvem? Não: KAFKA_BROKER=172.18.4.56:9093 por desenho (pedido de 25/11, "kafka local sempre"). Oferecido: inf_restrita.local.env com a nuvem (só na placa) ou mudar o .env.
- Falta: copiar o relatório para validacao/inf_restrita/evidencias/ (pedir ao usuário).

### 2026-11-25 — esclarecimento: "manter o kafka local" = container da placa sempre de pé; build na nuvem
- Feito: inf_restrita.env (nuvem; KAFKA_LOCAL_CONTAINER=kafka), inf_restrita.local.env.exemplo (placa), inf_restrita.sh (checar_kafka_local no subir/testar; status mostra o container e a origem do broker; mensagem de conflito pede ../i1/i1.sh parar), compose (comentários), guia, README, CLAUDE.md; memória kafka-local-significado.
- Validado: shellcheck, compose config (nuvem e com o .exemplo → placa), simulação dos 4 cenários.
- Commit pedido pelo usuário: 434a542 (inf_restrita na nuvem). Sem push. Pedido seguinte do usuário: tirar o I1 permanente (escopo a combinar; pergunta interrompida).

### 2026-11-25 16:25 — Jetson: inf_restrita na NUVEM: PASSOU 10, FALHOU 0, AVISO 0
- ./inf_restrita.sh testar com KAFKA_BROKER=34.66.235.91:9093 (nuvem respondeu: id 1); container kafka da placa Up 19 h; I1 permanente parado. 150 detecções (-fp16), 150 trilhas, contrato 100%. Relatório na placa: resultados/aceite-inf_restrita-20261125-162407.txt.
- Do notebook (fora da placa, só leitura, confluent-kafka): os 5 tópicos existem na nuvem com as mesmas contagens (command 1, detections 150, tracks 150, calibration 1, artifact.published 1) → acessíveis de fora.
- Disco 4 GB livres (no limite).

### 2026-11-25 — I1 volta a ler a pasta original dos vídeos (/home/sys2/SIS-2/videos)
- Placa (usuário): a pasta existe (dono sys2; INV1 76 MB, INV2, VER2, VER2_2, VER5 19 MB). Antes o I1 lia INV1.mp4 de assets/ do p3 (VIDEO_DIR montado em /videos + I1_VIDEOS_DIR).
- Feito: compose monta I1_VIDEOS_ORIGINAL no MESMO caminho, só leitura, create_host_path false; tirado I1_VIDEOS_DIR (vale o padrão do código); vídeos do P3 em /videos-p3. inf_restrita.sh: listar_originais via docker --mount (ods pode não ler /home/sys2), aviso se faltar a equipe do teste; status lista as duas pastas. Guia e CLAUDE.md.
- Validado fora da placa: shellcheck, compose config, simulação subir/status. Falta na placa: parar && subir && testar.
- Commit pedido pelo usuário: e1476e2 (pasta original dos vídeos). Sem push.

### 2026-11-25 20:04 — Jetson: I1 lendo a pasta original confirmado
- Log de partida: videos_dir='/home/sys2/SIS-2/videos', broker nuvem. Sem I1_VIDEOS_DIR. Montagens: /home/sys2/SIS-2/videos (rw=false), /var/lib/ods/videos -> /videos-p3 (rw=false).
- START INV1 (source_id conferencia-video): fd 51 -> /home/sys2/SIS-2/videos/INV1.mp4 (76764171 bytes). STOP enviado.
- Falta: ./inf_restrita.sh testar com a pasta original (não informado).

### 2026-11-26 — análise do P6 e das dependências (P's) da inf_restrita (só leitura, sem mudança de arquivos)
- P6 (main 0abc81e, 25/11; develop 50f0eb6 = main menos src/a.txt): listener Python (scripts/p6_listener.py) em python:3.12-slim, sem GPU; README diz que já roda na GCP. Replay publica em Kafka ods.session.started, ods.p4.frame (SÓ metadados, sem pixels: não há SHM/stream) e ods.p6.replay.state, a partir de gravacao_p6.mp4 (vtest.avi do OpenCV, 640x480, 795 quadros) embutido; "gravação" é simulada (só grava linha no SQLite, não consome P4/P5). Sem reply em replay.command. Broker: Dockerfile 200.17.66.56:9093 (IP público da Jetson; CLAUDE.md diz EXTERNAL 9094), kafka_client padrão 34.66.235.91:9093, README cita 172.18.4.56:9092 (anuncia localhost).
- Conclusão: pela 6c o P6 é camada 1 e substitui P4/P5 como fonte (pixels pelo pipeline de streaming) → deveria estar onde está o P4 (Jetson). Do jeito que está, não entrega quadros a ninguém; colocá-lo na placa não muda nada para o I1 (que lê SHM do P4 ou arquivo, não Kafka).
- inf_restrita: P2 sim (wheel 0.2.0a1 dentro da imagem do I1; existe 0.2.0a3); B5 sim (pacotes na develop do I1); P4 NÃO (orquestrador lê MP4 de /home/sys2/SIS-2/videos; I1_P4_DIR montado mas nenhum P4 na build); P6 não; P5/P7 não se aplicam. I2/I3 não consomem ods.session.started no código (grep). Sem P4, ninguém publica ods.session.started; o I1 gera o session_id sozinho.
- Próximo: resposta ao usuário; se ele quiser, compor P4 (perfil video, como no A8) na inf_restrita.

### 2026-11-26 — pergunta: inf_restrita está incompleta frente aos P's e B's?
- Resposta: completa para o "mínimo pelo código" pedido em 25/11; incompleta para a cadeia da 6c. Faltam P4 (quadros, captured_at, ods.session.started) e a validação pelos contratos centrais B1/B4 (hoje contrato/validar.py usa o schema do próprio repositório). P2, B5 e B3 (Kafka) presentes; B2 só parcial (sem fonte de sessão); P6 não funcional como fonte.
- Próximo: usuário decide se compõe o P4 (perfil video) e troca a validação para o B4/ods-validator.

### 2026-11-26 — pergunta: o que falta no P6
- DB: 1 cenário (rec-001 → videos/rec-001.mp4 inexistente), 795 linhas de frame_timestamps de UMA sessão (20/11), usadas para qualquer recording. Sem SEEK/RESTART/previous_session_id; LOOP não gera sessão nova. 3 testes (contrato, banco, estado).
- Resposta: lista de lacunas (pixels/streaming, gravação real, controle, sessão, replies, broker, empacotamento) → recado para TRA-2; P3 só compõe quando houver saída de quadros.

### 2026-11-26 — pergunta: modo mais performático da Jetson
- Resposta (comandos para o usuário rodar na placa): nvpmodel -q / conferir id do MAXN SUPER no /etc/nvpmodel.conf, nvpmodel -m <id> (pode pedir reboot), jetson_clocks (com --store antes; não persiste: serviço systemd se quiser), ventoinha; memória: modo texto (multi-user.target) libera RAM. Avisos: placa compartilhada (Kafka de outro grupo), fonte/temperatura, decisão pendente com SIS-1. Nada rodado.

### 2026-11-26 — Jetson: jetson_clocks aplicado (usuário)
- Estado salvo em /home/ods/clocks-original.conf. Depois: CPU 6× 1,728 GHz fixo, GPU 1020 MHz fixo (8 TPCs), EMC 3199 MHz, ventoinha 255 (máx.), modo NV 25W (MAXN SUPER não aplicado).
- Leitura: relógios já no teto do Orin Nano Super; o MAXN SUPER só tira o limite de potência (evita redução sob carga longa). Não persiste após reboot. Desfazer: sudo jetson_clocks --restore ~/clocks-original.conf.
- Próximo sugerido: medir (validacao/i1/testar-i1-tempo-real.sh ou ./inf_restrita.sh testar) e tegrastats; decidir MAXN SUPER e persistência (serviço systemd).

### 2026-11-26 — recapitulação: o que falta para os I's funcionarem plenamente
- Conferido: builds inf e inf_restrita SEM P4 (cada I lê arquivo). Recap por I (I1–I9) + transversais (P4, P2/engines, P5, P6, B1, Kafka nuvem, disco/memória, jetson_clocks). Só resposta; nenhum arquivo do repo alterado.

### 2026-11-26 — recorte: só os I's do A4 (I1, I2, I3)
- Descoberto: A4 main c280dea (26/11; build a4 do p3 fixa 9d6cbd4 de antes) roda na VM da GCP (compose.nuvem.yml: back, front, i3 p/ registro) e diz "O I1, o I2 e o I3 rodam na Jetson (camadas 1-2, homologação); o S1, o S4 e o P7 usam o mesmo broker". A4 manda ods.i1.command START/HEARTBEAT(20 s)/STOP, câmera INV1 (source_id = equipe); A4_RELOGIO_QUADRO contorna o captured_at do I1 (carimbo na leitura). Consome ods.s1.position, ods.i3.calibration, ods.p7.state, ods.s4.clip, ods.session.started.
- I3 main agora 0a7f944 (25/11: "quadra do A4 com source_id INV1"); inf_restrita fixa c3d876e e calibra source_id inf-restrita-quadra (só teste).
- I1 develop: app-sports 1.2.0 (classe ball, 1280) já em I1_PACOTES.
- Lacunas: S1 (entre I2 e A4) em nenhuma build da placa (quem roda?); I3 desatualizado e sem calibração INV1; onde roda o I3 (VM e/ou Jetson); teste com START real do A4 nunca feito; captured_at do I1; sem P4 (arquivo INV1.mp4); I2 não reinicia por sessão; builds/a4 do p3 desatualizada.

### 2026-11-26 — inf_restrita: I3 atualizado para 0a7f944
- Usuário: S1 roda na nuvem; A4 já existe (na nuvem). Pedido: atualizar o I3 e dizer o que mudou.
- c3d876e → 0a7f944: só HOW_TO_RUN.md (roteiro da Jetson, Kafka da nuvem 34.66.235.91:9093, quadra do A4 com source_id INV1; cal-INV1-1 já publicada pelo INV-1). Código idêntico; Dockerfile não copia o .md → imagem com o mesmo conteúdo.
- Arquivos: builds/inf_restrita/inf_restrita.env (I3_REF), docker-compose.yml (comentário: I3 daqui calibra só o source_id do teste, para não concorrer com a cal-INV1-1), GUIA-BUILD-INF-RESTRITA.md, CLAUDE.md §5. builds/inf continua em c3d876e.
- Validado só local: YAML ok (python yaml), ref confere com ls-remote, diff de código vazio. Sem docker compose config (download do binário negado pelo modo auto).
- Na placa: em vez de reconstruir, docker tag ods-i3:c3d876e… ods-i3:0a7f944… (mesma imagem, 0 bytes); depois ./inf_restrita.sh testar.
- Próximo: commit (aguarda usuário); teste de ponta a ponta com partida real do A4.

### 2026-11-26 — levantamento: build inf × dependências P/B da 6c (pergunta do usuário)
- Feito: lido o mapa "Entradas de cada componente" da 6c (ods-6cfinal.html, seção 9) e o código dos I's nos commits do inf.env (clones no scratchpad).
- Resultado: P2 só no I1 (build i1) e no I7 (GPU); nenhum I da inf lê o P4 hoje (todos por arquivo); I8 em mocks (sem I1/P4/P2); I9 sem P4/P2 (só stdlib); teste da inf conta mensagens, não valida contrato (B1/B4).
- P4 nativo (usuário: P4 roda na placa fora de container): o P4 grava o socket fixo em /tmp/p4_file_shm; o I1 permanente monta I1_P4_DIR=/var/lib/ods/p4-shm em /tmp → não enxerga. Precisa I1_P4_DIR=/tmp. I7 precisaria de ipc host + /tmp + --p4. I6 espera TCP, não lê P4.
- Próximo: aguardar o usuário decidir se liga P4 no I1/I7.

### 2026-11-26 — pergunta: falta incluir algum componente na inf_restrita para I1/I2/I3?
- Resposta: não, no arranjo de hoje (vídeo em arquivo, A4/S1/I3-registro na nuvem). P2/B5 já dentro da imagem do I1. Só o P4, se quiserem câmera ao vivo (cadeia da 6c). Pré-condições fora da build: Kafka da nuvem ligado, I1 permanente parado, INV1.mp4 na pasta da SIS-2, engine app-sports em /var/lib/ods/engines.

### 2026-11-26 — pedido: renomear inf_restrita → inf_a4 + scripts guardar/subir pelo notebook + commit
- Plano: git mv builds/inf_restrita → builds/inf_a4 e validacao/inf_restrita → validacao/inf_a4 (guia GUIA-BUILD-INF-A4.md); trocar referências (ods.sh, README, CLAUDE.md, testar-inf-repos.sh, testar-i1-servico.sh); projeto ods-inf_a4, grupo ods-i1-inf-a4 (I1 usa auto.offset.reset=latest: grupo novo não relê comandos), source_id/versão do teste do I3 inf-a4-*.
- Scripts (rodam NO NOTEBOOK, ssh na placa, sem arquivo na placa): builds/inf_a4/guardar-no-notebook.sh (ssh docker save | zstd → ~/ods-imagens/inf_a4-<data>/; engines por tar num container root; manifesto) e builds/inf_a4/subir-do-notebook.sh (confere refs e disco, zstd -dc | ssh docker load, engines, ./inf_a4.sh subir).
- Na placa, antes do git pull: ./inf_restrita.sh parar (projeto antigo); depois mover resultados/.
- Commit: só I3 + renomeação + scripts (A2 continua fora).

### 2026-11-26 — inf_restrita → inf_a4 + scripts do notebook (feito)
- Arquivos: git mv builds/inf_restrita → builds/inf_a4 (inf_a4.sh/.env/.local.env.exemplo), validacao/inf_restrita → validacao/inf_a4 (GUIA-BUILD-INF-A4.md); referências em ods.sh, README, CLAUDE.md, testar-inf-repos.sh, testar-i1-servico.sh. Projeto ods-inf_a4, grupo ods-i1-inf-a4, source_id/versão do teste do I3 inf-a4-quadra / cal-inf-a4-quadra-1. Nome histórico aceite-inf_restrita-20261125-* mantido no guia.
- Novos: builds/inf_a4/guardar-no-notebook.sh e subir-do-notebook.sh (rodam no notebook; ssh com ControlMaster; docker save|zstd e zstd -dc|docker load; engines por tar num container da imagem do I3; manifesto + SHA256SUMS; confere *_REF do p3 da placa; disco = tar + 4 GB, FORCAR=1).
- Achado na simulação: python3 do notebook é atalho do asdf sem versão nesta pasta → scripts sem python (só zstd/tar/awk).
- Validado: bash -n em todos; simulação (scratchpad/sim, ssh e docker falsos): guardar, subir, 2ª subida, commit diferente, placa sem build, imagem ausente, pasta corrompida, disco insuficiente. Sem shellcheck e sem docker compose config (binários ausentes; download negado).

### 2026-11-26 — opção de comprimir/descomprimir na placa (usuário em casa, sem acesso ao lab)
- Contexto: de casa, 172.18.4.56 não responde; sem alias no ~/.ssh/config. Os scripts aceitam JETSON=<endereço> (ex.: ods@200.17.66.56, se o ssh estiver aberto para fora: não testado).
- Feito: guardar-no-notebook.sh --comprimir-na-placa e subir-do-notebook.sh --descomprimir-na-placa: zstd na placa se houver, senão pigz/gzip (nice 19), via bash -o pipefail na placa; pasta no notebook continua .zst; manifesto ganha COMPRESSAO_NA_PLACA. Guia §4.1 e CLAUDE.md.
- Validado só na simulação: placa com zstd e só com gzip (guardar e subir), docker save falhando no meio → erro e pasta .parcial, modo padrão inalterado. Sem commit (aguarda usuário).

### 2026-11-26 — pergunta: como conferir o P4 (/home/sys2/SIS-2/p4) e a ligação P4 → I1
- Lido (GitHub p4 main 640e19e, 06/11; conferir se a pasta da SIS-2 é a mesma): roda nativo com venv (scripts/p4_demo.sh video|imx519|imx477|kafka; p4_ler.sh lê 1 quadro e grava PNG); socket FIXO no código: /tmp/p4_file_shm (arquivo), /tmp/p4_imx519_shm, /tmp/p4_imx477_shm; shmsink wait-for-connection=false (toca sem esperar leitor); vídeo padrão ../videos/cars_extended.mp4 (P4_VIDEO_PATH muda); Kafka desligado no modo video. 20 testes unittest.
- I1 3b2a9cc: START com "source": "video"/"file"/"/tmp/p4_file_shm" → P4GStreamerShmSource (mesmas caps application/x-ods-frame,version=1 e cabeçalho P4R1: formato compatível).
- PROBLEMA: na inf_a4 o /tmp do I1 é /var/lib/ods/p4-shm da placa (I1_P4_DIR), e o P4 nativo cria o socket no /tmp da placa → o I1 não o vê. Contorno sem editar código: inf_a4.local.env com I1_P4_DIR=/tmp (reversível) e ./inf_a4.sh parar && ./inf_a4.sh. ipc: host já dá o /dev/shm.
- Próximo: usuário roda o roteiro (P4 sozinho → P4 + I1) e traz a saída; oferecer ./inf_a4.sh p4 se quiser automatizar.

### 2026-11-26 — ./inf_a4.sh p4 (P4 da SIS-2 → I1), feito
- Arquivos: inf_a4.sh (p4_testar, p4_ligar_tmp, p4_desfazer, parar_p4, resumo_tempos, esperar_i1_pronto extraída do pos_subida; trap encadeado com o da lib; vivo() por /proc porque kill -0 no sudo dá EPERM), inf_a4.env (P4_DIR, P4_USUARIO, P4_VIDEO, INF_P4_EQUIPE, INF_P4_QUADROS), guia §4.0, CLAUDE.md (§5 e pendência SIS-2).
- Achado: com P4 como fonte, o I1 publica com source_id/session_id do cabeçalho do P4 (file_INV1); o A4 espera INV1.
- Validado só em simulação (scratchpad/simp4: docker, sudo e P4 falsos): feliz PASSOU 6; 2ª vez sem recriar; trava ocupada → recusa; socket velho → apagado; P4 não sobe → sem START, FALHOU 5; erro do I1 → T-P4S/I/C/G FALHOU; equipe ocupada → aviso; --desfazer mantém as outras linhas do local.env. Defeitos achados e corrigidos na simulação: python3 falhando derrubava o relatório (set -e); T-P4G passava sem mensagens.
- Próximo: commit (aguarda usuário); na placa: git pull e ./inf_a4.sh p4.

### 2026-11-26 — regra do usuário: nada do P4 nem de /home/sys2 pode ser alterado
- Revisão do ./inf_a4.sh p4: git status regravaria .git/index → git --no-optional-locks; p4_demo/p4_ler gerariam __pycache__ em src/ → PYTHONDONTWRITEBYTECODE=1; socket velho de outra execução era apagado → agora para e avisa (só apaga o socket criado pela própria execução, no /tmp). Regra no CLAUDE.md §4, guia e memória sys2-somente-leitura.
- Simulação: feliz PASSOU 6; socket velho → para sem apagar; PYTHONDONTWRITEBYTECODE=1 chega ao P4.
- Pergunta 2 (salvar imagens de novo?): não — só scripts e .env mudaram; I1/I2/I3_REF iguais (tags e ids das imagens iguais); o subir-do-notebook confere só os *_REF.

### 2026-11-27 01:18 (UTC) — Jetson: 1ª execução do ./inf_a4.sh p4 (logs trazidos pelo usuário; relatório .txt não veio)
- P4 (INV1.mp4, 1280x720, 29,97 q/s, Kafka off) subiu 01:18:27, socket /tmp/p4_file_shm; p4_ler leu o quadro 15 (file_INV1, sessão 07ed21d5…) → RECEBIMENTO VALIDADO.
- I1: START 01:18:34; "Carregando app-sports-1.2.0" 01:18:34 → 1º quadro 01:18:48 (frame_index 616: ~13,5 s de carga; perdeu ~20 s de vídeo); 150 quadros até 01:18:56,5 (~8,3 s → ~18 q/s processados com o P4 a 30: appsink drop=true descarta); sessão encerrada max_frames_reached. source_id/session_id do P4 propagados (file_INV1, 07ed21d5).
- Kafka (nuvem): command +1, detections +150, tracks +150 (I2 rastreou tudo).
- Observações: P4 modo arquivo manda "timestamp": null → I1 usa a hora da leitura como captured_at (B2-OBS: captured_at 2 ms antes do log): o T-P4T mede processamento do I1, não P4→I1. "lsmod/modprobe not found" no container: inofensivo. Carga de 13,5 s possivelmente pelo drop_caches (engine lida a frio do cartão) — não confirmado.
- Próximo: usuário traz resultados/p4-i1-*.txt (T-P4*) e faixa de frame_index; ./inf_a4.sh p4 --desfazer; evidência em validacao/inf_a4/evidencias/.

### 2026-11-27 — recado à SIS-2: timestamp nulo no modo arquivo do P4
- Causa no código (p4 main 640e19e): src/p4.py, ramo timestamp_origin == "file_playback_raw" põe captured_at_ns = None de propósito (comentário: reprodução, não captura física); vai como "timestamp": null no cabeçalho SHM e no ods.p4.frame. Câmeras (driver_*) preenchem. O I1 (ingestion.py) só lê "timestamp" e, nulo, usa a hora da leitura.
- Recado entregue ao usuário (texto para enviar); pendência na tabela §8 do CLAUDE.md (linha SIS-2/MOD-2).

### 2026-11-27 — pedido: levantar todas as infs; checar I4 e I5; criar journal.md
- Registrado como tarefa (não fazer agora): recado à MOD-1 (I1 ler received_at_* quando o timestamp do P4 vier nulo; combinar relógio MONOTONIC × MONOTONIC_RAW).
- Plano: clonar i4/i5 no scratchpad, comparar com I4 503f64b / I5 d7b1379 (build inf) e as pendências do CLAUDE.md §8; criar journal.md na raiz (pedidos, estado, pendências, tarefas, mensagens, resultados).

### 2026-11-27 — levantamento das infs e journal.md (feito)
- I4 main = 503f64b (nada novo; pyarrow/mediapipe/webcam/s6 iguais). I5 main 4d79472 (25/11): base l4t-tensorrt r10.3 (JP6 ok), sem torch → src/p2_runtime.py (imitação local do P2) devolve texto fixo "Transcrição processada via engine acelerado P2": transcrição falsa. I6 main 89143c9: lê P4 por SHM (I6_SOURCE_MODE). I2 5f4957c e I3 0a7f944: só docs. I7/I8/I9 iguais.
- Arquivos: journal.md (novo, raiz), CLAUDE.md (§0 regra do journal; §8 I4/I5/I6), PROGRESSO arquivado (13–18/11 → temp/PROGRESSO-arquivo-2026-11-27.md). Push dos commits de 26/11 já feito (main = origin/main).
- Próximo: decisões do usuário (ver Estado atual).

### 2026-11-27 — decisões do usuário para levantar todas as infs
- I5 fora + recado à VER-4; a inf passa a usar o I1 (e o I2) da inf_a4, sem o I1 permanente; I2 → 5f4957c, I3 → 0a7f944, I6 → 89143c9.
- Plano: inf sem i2 próprio (evita trilhas em dobro), container_i1 = ods-inf_a4/i1, pedido ao I1 com "source": "/videos-p3/<EQUIPE>.mp4" quando o vídeo do P3 existe (VER3 não está na pasta da SIS-2); ods.sh trocar inf mantém e sobe a inf_a4 antes; inf_a4 I2 → 5f4957c (docker tag na placa).

### 2026-11-27 — inf sobre a inf_a4 (feito, sem commit)
- Arquivos: inf/inf.env (I2 5f4957c, I3 0a7f944, I6 89143c9; comentário do VER3), inf_a4/inf_a4.env (I2 5f4957c), inf/docker-compose.yml (i2 comentado com motivo e como desfazer; cabeçalho), inf/inf.sh (container_i1/i2 = ods-inf_a4; checar_i1 confere I2 e avisa do I1 permanente; pedir_i1 com "source": "/videos-p3/<EQUIPE>.mp4" se existir; ETAPAS e aceite_conferir sem i2; status), validacao/inf/testar-inf-repos.sh (R-I1 no i1 da inf_a4), comum/lib.sh (--manter repetível), ods.sh (base_de: trocar inf mantém e sobe a inf_a4), guia da inf, README, CLAUDE.md, journal.md (recado VER-4 em §4.2).
- Validado: bash -n (inf.sh, ods.sh, lib.sh, testar-inf-repos.sh), YAML do compose da inf, simulação do trocar. Não rodado: docker compose config (sem binário), placa.
- Na placa: o I2 da inf_a4 muda de etiqueta (docker tag) → o subir recria o container i2.

### 2026-11-27 — I4 e I5 fora da build inf (pedido do usuário)
- I4 comentado no compose (i4-server, i4, i4-video, com motivo e como voltar), ETAPAS ("i3 i6 i9" "i8" "i7"), aceite_conferir i6 i9, disparo comentado, T-I4 = AVISO, ./inf.sh i4 recusa; testar-inf-repos.sh: i4 fora de TODOS e recusado; inf.env nota; guia, README, CLAUDE.md, journal.
- Validado: bash -n, YAML (serviços: i3 i6 i6-gerar-video i7 i8 i9 kafka-topicos).
- Atenção: imagens ods-i4* já na placa ficam órfãs (nenhum compose as lista): remoção manual, só se o usuário pedir.

### 2026-11-27 — pergunta: com a placa vazia sobe I1–I9 menos I4/I5? O que dispara I3/I7/I8?
- Resposta: só via ./ods.sh trocar inf (base_de sobe a inf_a4: I1 + I2 contínuos, engines); ./inf.sh sozinho só avisa que falta o I1. A inf constrói i3/i6/i8/i9/i7 e deixa de pé i6/i9. I3/I7/I8 = perfis one-shot: rodam só com ./inf.sh i3|i7|i8 ou no ./inf.sh testar (compose run --rm, processam a entrada e saem). I1 também só trabalha com START.
