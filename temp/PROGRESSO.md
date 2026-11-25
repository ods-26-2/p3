# Progresso — builds ODS (P3)

## Estado atual
- Aplicação em foco: build "inf" (todas as inferências I1–I9; uma pasta, uma seção do compose por I; I1 = builds/i1)
- Fase: build na Jetson parou por disco cheio na última imagem (I7); I7 trocado para GPU (ods-i7-gpu), validado só fora da placa
- Último resultado: todas as imagens da inf na placa menos a do I7; simulação do T-I7 GPU ok
- Próximo passo: na placa ./inf.sh status e ./inf.sh testar (todas as imagens da inf existem, inclusive ods-i7-gpu; suítes das equipes já rodadas: 5 PASSOU, I4 pyarrow, I6/I7 sem suíte)
- Bloqueios / perguntas abertas ao usuário: Kafka da nuvem (TRA-1) desligado; imagens ods-i5* d7b1379 de quem?; dica "../ods.sh trocar" da lib para build permanente; A2 segue sem commit
- Continuidade: este arquivo e o CLAUDE.md foram versionados a pedido do usuário (13/11/2026); temp/ segue no .gitignore (PROGRESSO.md entrou com git add -f).

## Registro
### 2026-11-13 — início
- Feito: lidos CLAUDE.md, builds/a8/* e ods-6cfinal.html (enviado na conversa)
- Pedido do usuário: finalizar A8 (limpar.sh), builds A1–A7, script para rodar tudo de uma vez e script de limpeza (só uma app cabe na placa por vez). Foco em composes e preparação; validação fica para depois.
- Ambiente: sem docker compose, shellcheck, pyflakes locais.

### 2026-11-13 — levantamento A1–A7 (clones em scratchpad/src, fora do repo)
- A1 (main 5d17305): backend FastAPI+Postgres, frontend nginx (proxy fixo p/ "backend:8000"). Consome ods.industria.defeito_classificado (não ods.i8.piece_analysis). S4 via S4_ENABLED=1. P7/S5 só fakes.
- I8 (main 051851f): sem modelo treinado no repo; caminho real = publisher (scripts.publish_events) com mocks shared/mocks/kafka-2.0 (Dockerfile.publisher).
- A2 (develop 708b2dd; main muito atrás): container único (liberar.py + API 8001, monitor 8000). Consome ods.i6.code_read; S4 por TESTE_S4=false. Precisa A2_AES_KEY (32 bytes).
- I6 (develop ff1bf44): DetectorQR. Modo teste lê URL de câmera OU arquivo (relê em laço). Modo P4 espera socket TCP que o P4 não oferece.
- A3 (dev 5a102e9): Streamlit sem Dockerfile/requirements; broker FIXO 34.66.235.91:9093 no código. Consome s1.zone_transition, s2.entity, s2.event; publica s3.alert.command.
- S2 (develop e611a51): continua sem Kafka.
- S3 (main d45bbfa): Dockerfile pronto; S3_KAFKA_BOOTSTRAP; --routing <arquivo> (sem routing = só comandos). Nota do S3: desde 11/11 a 9092 anuncia kafka:9092; 9093 não afetada.
- A4 (main 9d6cbd4): back FastAPI e front Next.js SEM Dockerfile. Consome s1.position (classe "ball"), i3.calibration, p7.state, s4.clip, session.started. Modelo app-volei (classe ball) no próprio repo -> I1 --onnx/--metadata.
- A5 (main c634433): Dockerfiles prontos (backend 8000, front nginx 8095 com proxy p/ "backend"). A5_BUS=kafka.
- I9 (main 8ae3933): sem Dockerfile; python main.py --kafka (KAFKA_BOOTSTRAP_SERVERS). Dataset de 323 MB no repo (não copiar para imagem). Sem modelo EPI publicado p/ I1 (só app-plates).
- A6 (main 7f47b39): Dockerfile pronto (8080), KAFKA_BOOTSTRAP_SERVERS. Mock S6/I4 integrado (--no-mock desliga os dois).
- I4 (main 61b39a1): repo traz também o S6 (s6_synthesis/bus_service.py) e publicador de amostra (pipeline/publica_amostra.py); ODS_KAFKA_BOOTSTRAP; imagem leve (numpy/pandas/pyarrow/confluent-kafka). Ao vivo depende de servidor C++ próprio (fora).
- I5 (main cdb00d2): sem Dockerfile; modo arquivo src/pipeline.py <audio> --publish-kafka; torch+transformers+whisper-small (pesado).
- A7 (main 3503a26): sem Dockerfile; main.py --server --port 8000; KAFKA_ENABLED=1, KAFKA_BOOTSTRAP_SERVERS; SLM via ollama (fallback RapidFuzz). S5 opcional (tópico ods.s5.event.metrics, fora da spec).
- P5, P7: só scripts de hardware, sem Kafka/serviço. P6: develop tem protótipo. S6 repo vazio.
- Próximo: decidir estrutura (builds/comum/lib.sh + ods.sh orquestrador) e escrever composes.

### 2026-11-13 — decisão de estrutura
- builds/comum/lib.sh: funções de subir/status/parar/limpar compartilhadas pelas apps novas (a8.sh validado fica como está; só ganha limpar.sh, que usa a lib).
- builds/comum/preparar-codigo.sh <env>: clona todo repo com <REPO>_REF no env (cada app tem preparar-codigo.sh fino).
- builds/comum/kafka_override/sitecustomize.py: contorno p/ código com broker fixo (A3), sem editar o código da equipe.
- builds/ods.sh: orquestrador (lista, trocar <app>: limpa as outras mantendo imagens que a nova usa, depois sobe).
- Padrão das apps: como o A8 — serviços contínuos no "up"; fontes (p4/i1, i3, i5, i8, i4-amostra) em perfis sob demanda.
- Portas: A1 5500 (+127.0.0.1:8010 back); A2 8000/8001 (+8082 crachá); A3 8501; A4 3000/8000 (+S4 18084 aberto p/ replay no navegador); A5 8095 (+127.0.0.1:8000); A6 8086; A7 8000.

### 2026-11-13 — escritos
- builds/comum/{lib.sh,preparar-codigo.sh,kafka_override/sitecustomize.py}; builds/a8/limpar.sh; builds/a{1..7}/{preparar-codigo.sh,limpar.sh}; builds/a1/* completo.
- Segredos por app: A1_DB_PASSWORD; A2_AES_KEY; A4_TOKEN; A5_ADMIN_SENHA; A3/A6/A7 sem segredos.
- Próximo: A2, A3, A4, A5, A6, A7 (compose, env, <app>.sh), depois builds/ods.sh e validação local.
- 05:02 A2, A3, A4 escritos (compose, env, sh, artefatos). Próximo: A5, A6, A7, ods.sh.
- 05:06 A5, A6, A7 e builds/ods.sh escritos. Download de docker compose/shellcheck NEGADO pelo modo auto: validar com bash -n + checagem Python; docker compose config fica para o usuário.

### 2026-11-13 — validação local
- bash -n em todos os .sh; checar_builds.py (scratchpad) sem problemas além dos esperados do A8.
- docker falso: ods.sh lista/trocar, limpar --imagens --manter, --dados (confirmação), subir A1–A7 ok. Corrigido: --help com $0 relativo.
- sitecustomize testado com confluent_kafka falso.
- Documentação: builds/README.md; CLAUDE.md seções 5 e 8 atualizadas.

### 2026-11-13 — sessão 2: "partes deixadas para depois" = validação
- Plano: (1) builds/comum/aceite/ods_aceite.py + builds/<app>/aceite/aceite_<app>.py + função testar em cada <app>.sh (perfil aceite, B4_REF no env para o validador);
  (2) validacao/validacao-geral/validar-sistema.sh <app> (S1–S9) + validacao/<app>/{validar-<app>-fluxo.sh,README.md,RELATORIO-VALIDACAO.md,evidencias/}.
- Onde não há produtor real (S2 sem Kafka, modelo EPI, QR em vídeo), o teste injeta a mensagem e marca o item como SIMULADO.
- Levantamento p/ testes: A1 GET /api/v1/inspections (origin.message_id, evidência); A2 /acessos (i6_message_id, media_status) e QR = hex AES(cpf,início,fim); A4 /health (calibracoes_carregadas), /p6/deteccoes, /camera/enquadrar, /partidas; A5 /auth/login (administrador), /alertas, /alertas/{id}/ack; A6 /api/state, /api/translate; A7 /sessoes/{origem}; I5 publica payload fora da 6c (texto_transcrito...).
- A3: motor Kafka só liga quando alguém abre o painel (st.cache_resource na sessão) -> testar pede para abrir o navegador.
- 05:27 escritos: comum/aceite/ods_aceite.py, funções aceite_* na lib, aceite_a1..a4.py. Próximo: aceite_a5..a7, serviço aceite nos composes, testar() nos .sh, validacao/.
- 05:35 aceite_a1..a7 + serviço aceite + testar() + B4_REF; testados contra Kafka falso (falha e sucesso). validacao-geral/{validar-sistema.sh,fluxo-comum.sh}, validacao/a1..a7/validar-*-fluxo.sh (dry-run ok). Próximo: README/RELATORIO por app, docs, checagem estática.

### 2026-11-13 — validação concluída (fora da placa)
- READMEs e RELATORIO-VALIDACAO.md (modelo, com resultado esperado) em validacao/a1..a7; validacao/README.md, builds/README.md e CLAUDE.md atualizados.
- Corrigidos durante os testes: A4 quebrava com API fora do ar; A2 dava falso PASSOU no crachá vencido com API fora do ar; esperar_passo sem poll (consumidor sairia do grupo).

### 2026-11-13 — análise do A8 (pedido: testar o mais perto do uso real e achar falhas)
- A8 66af0ba é o último da main; I7 tem development a6ded08 (detector via P2/ONNX app-plates) mais nova que a main fixada.
- Achados: decisão de acesso não é gravada (só log); baixa_confianca (~26% das leituras, doc do A8) sem tela/rota de conferência manual; saída usa a mesma regra da entrada (convidado vencido não sai); sem filtro por empresa (CNPJ); cancelas fixas no código (cam-entrada/cam-saida); I7 só lê pasta de imagens; cadeia P4..S5 da build não é consumida pelo A8.
- Integração I7->A8 coerente: confidence = mínima por caractere, uncertain = mín < 0,9 = limiar do A8; occurred_at = captured_at; placas normalizadas iguais; datas de convidado em horário local dos dois lados.
- Teste atual do P3 (a8.sh testar) não cadastra veículo: só exercita nao_cadastrado/baixa_confianca.
- Corrigido: REACT_NATIVE_PACKAGER_HOSTNAME no a8-frontend (Expo Go no celular).
- Execução da suíte de testes do A8 (node --test) negada pelo modo auto.

### 2026-11-13 — A8: I7 lendo o vídeo cam0.mp4 (está na Jetson, não aqui)
- builds/a8/i7/extrair_quadros.py (P3): extrai I7_QUADROS_FPS quadros/s do vídeo dentro da imagem do I7 (OpenCV).
- compose: serviço i7-video (perfil i7, imagem ods-i7, volume i7-quadros); a8.env: I7_FONTE=video, I7_VIDEO, I7_QUADROS_FPS, I7_QUADROS_MAX.
- a8.sh: novo comando placas-video; testar usa o vídeo quando I7_FONTE=video.
- Validado: bash -n, checagem estática, docker simulado (ordem das chamadas), extrator com cv2 falso. NÃO rodado na Jetson; conteúdo do vídeo desconhecido (não sei se tem placas legíveis).

### 2026-11-13 — commit A8
- Branch builds/a8-limpeza-e-video, commit 850f45b (11 arquivos: builds/a8/*, comum/lib.sh, ods.sh, validar-sistema.sh, validacao/a8, .gitignore). Sem push. A1–A7, comum/aceite, kafka_override, preparar-codigo comum, fluxo-comum, READMEs gerais e CLAUDE.md ficaram fora.
- Merge fast-forward em main e push: origin/main = 850f45b.

### 2026-11-13 — análise do A6 (completude, subida, tempo)
- A6 7f47b39 e I4 61b39a1 são os últimos da main; repo s6 segue vazio.
- Léxico do A6: 100 glosas; S6 real (i4/s6_synthesis) só tem 20 (MINDS-Libras). Glosa toda desconhecida -> S6 responde EMPTY_SEQUENCE.
- A página do tradutor usa SEMPRE o mock interno (trajetória-modelo 6d9c234fcd35.json repetida); a reply do S6 real só vai ao log. Avatar .glb animado exige Blender (fora da imagem).
- I4 reconhece 20 sinais; ao vivo depende de servidor C++ (Crow, websocket H.264) + mediapipe + torch: fora da build. A6 normaliza "Aluno" -> ALUNO (ok).
- Corrigido teste: frase "aluno conhecer banheiro"; C07 mede cobertura do léxico no S6; C08 AVISO tela=mock. Relatório e fluxo do A6 ajustados.
- Build do A6 NÃO está no GitHub (só A8 foi enviado); depende também de comum/preparar-codigo.sh e comum/aceite.

### 2026-11-13 — commit A6
- Branch builds/a6, commit 262af85 (builds/a6, comum/aceite, comum/preparar-codigo.sh, validacao/a6, fluxo-comum.sh). Sem push.

### 2026-11-13 — A8: componentes e idempotência do ./a8.sh subir
- Componentes: I1 I2 I3 I7 P4 S1 S4 S5 montados; P2 dentro do I1; S2 fora (develop e611a51 ainda sem Kafka); I6 opcional e não consumido. Nenhum repo com main mais nova que o fixado (só I7 development e S5 feat/s5-demo).
- Não idempotente: (1) esperar_servicos conta containers de perfis já terminados (p4/i1/aceite) -> 2º subir após testar falha; (2) imagem com mesma tag não é reconstruída se a receita do P3 (dockerfile_inline) mudar; (3) preparar-codigo faz fetch sempre (exige rede), não trata clone pela metade/alterações locais; (4) sem a8.secrets.env para; trocar a senha com banco existente quebra o backend em silêncio (mysqladmin ping passa com senha errada).
- Correções em andamento: a8.sh e a8/preparar-codigo.sh.
- Corrigido (sem commit ainda): a8/preparar-codigo.sh (fetch só se faltar commit; clone pela metade; alterações locais; erro claro de permissão em SRC_DIR); a8.sh: garantir_segredos (gera senhas se não há banco; para se há banco), checar_pastas, construir com hash da receita (.estado-imagens, gitignorado), esperar só serviços do up, teste da senha no MySQL. Exemplo de segredos atualizado.
- Testado com docker simulado: do zero (gera segredos, 4 etapas de build), 2ª subida (0 builds), receita do p4 mudada (só p4), sem segredos com banco (para), imagem refeita por fora (0 builds), espera com p4/i1/aceite terminados (versão antiga falha, nova passa).

### 2026-11-13 — commit idempotência A8
- Branch builds/a8-idempotente, commit bb67c9f. Sem push.

### 2026-11-13 — análise do I1 com TensorRT (develop cb5c381193840c1e189032820d971c00d541b225)
- Pedido: avaliar se o novo Dockerfile.jetson + artefatos bastam para o I1 inferir em GPU/TensorRT.
- Achados (só leitura de código, fora da Jetson):
  - main continua em 30df178; a mudança está só na develop (cb5c381, 13/11).
  - Dockerfile.jetson: base nvcr.io/nvidia/l4t-jetpack:r36.4.0 (grande; ods/base-gpu do SIS-1 é l4t-cuda runtime, sem TensorRT), p2[trt,cpu] v0.2.0a1, ENV P2_BACKEND=trt (sem queda silenciosa p/ CPU).
  - Não há engine no repo: só ONNX + metadata (app-plates, app-epi [pessoa/capacete/colete], app-industry, app-sports 1280). Engine é compilada na placa com p2-build (serviço i1-p2-build). ONNX estáticos, saída = 4+classes: passam nas checagens do p2-build.
  - Corrigido no I1: import os / BROKER_ENV_VAR (contorno do compose pode sair). Continua: saída código 1 no fim do vídeo (detector/ não mudou).
  - pyflakes limpo. Precisão padrão do P2 no TRT = FP16; envelope leva artifact_version = engine_version (app-plates-1.0.0-fp16) -> serve de prova.
  - Build do P3 (a8 e demais) ainda usa I1_REF=30df178, Dockerfile CPU e --backend ultralytics: nada muda sem alterar o compose.
- Próximo: usuário decide se adapta o compose (i1 com Dockerfile.jetson + runtime nvidia + one-shot p2-build + volume de engines) e confere na Jetson: imagem l4t-jetpack presente?, docker info runtime nvidia, df -h.

### 2026-11-13 — decisão: I1 em GPU na build do A8 + teste individual do I1
- Usuário pediu: adaptar a build para o Dockerfile.jetson; commit (usuário dá push e testa na Jetson); teste individual do I1 com as fixtures do repo.
- Plano: I1_REF=cb5c381 (develop); imagem ods-i1-gpu:<ref>; one-shot i1-engine (perfil video) com builds/comum/i1/preparar-engine.sh (p2.load ok -> pula; senão p2-build --precision FP16 --force); engines em /var/lib/ods/engines; p4 espera o i1-engine; a8.sh compila a engine no subir; validacao/i1/testar-i1-gpu.sh (fixtures app-plates, stdout, sem Kafka).

### 2026-11-13 — I1 em GPU no A8 + teste individual (escrito, não rodado na Jetson)
- Arquivos: builds/a8/{a8.env,docker-compose.yml,a8.sh}, builds/comum/i1/preparar-engine.sh, validacao/i1/{testar-i1-gpu.sh,README.md}, .gitignore (validacao/*/resultados/), CLAUDE.md (seções 5, 6 e 8).
- a8.sh: checar_gpu (runtime nvidia), pasta I1_ENGINES_DIR, preparar_engine_i1 depois do construir; IMG[i1]=ods-i1-gpu.
- Validado fora da placa: bash -n; YAML e variáveis do compose; testar-i1-gpu.sh contra docker/tegrastats falsos (sucesso, fp32/GPU 0%, sem runtime nvidia). Bug achado e corrigido: parse do GR3D_FREQ pegava o "3" de GR3D.
- Sem docker compose local: config real só na Jetson.
- Próximo: commit; usuário dá push e roda na Jetson: git pull; cd validacao/i1 && ./testar-i1-gpu.sh; depois cd builds/a8 && ./a8.sh subir && ./a8.sh testar.

### 2026-11-13 — versionamento para continuar em outro computador
- Pedido do usuário: commitar progresso e o necessário para continuar em outro computador.
- Entram no Git: temp/PROGRESSO.md (git add -f), CLAUDE.md, builds/README.md, builds/a1–a5, a7, builds/comum/kafka_override, validacao/a1–a5, a7, validacao/README.md (alteração pendente), faltaA8.md.
- Conferido antes: sem segredos (secrets.env.exemplo vazios), sem arquivos grandes.

### 2026-11-14 — Jetson: disco com 2 GB livres, a8.sh subir parou na checagem
- Saída do usuário: `docker build prune -af` (comando errado; o certo é `docker builder prune -af`); `./a8.sh subir` parou em "só 2 GB livres".
- docker ps -a: A6 de pé (ods-a6-s6-1, ods-a6-a6-1); ods-a6-kafka-topicos-1 é o one-shot de tópicos do A6 (Exited 0), NÃO é broker; broker só o "kafka" da turma (Up 3 days). Também a1-db-1 (outro grupo) e a8-mysql antigo (fora do projeto ods-a8), ambos parados.
- Suspeita: build do testar-i1-gpu (base l4t-jetpack, vários GB) + cache de build (se o build falhou, o script sai antes do prune) + A6 ainda instalado + ods-i1:30df178 (CPU, sem uso no A8 agora).
- Resultado do testar-i1-gpu.sh ainda não trazido pelo usuário.
- Próximo: usuário roda diagnóstico (builder prune certo, docker system df, imagens por tamanho, relatório do teste) e libera espaço (./ods.sh trocar a8 remove o A6).

### 2026-11-14 — resultado na Jetson: imagem de 16,5 GB; troca da base
- Saída do usuário: ods-i1-gpu:cb5c381 = 16.5GB; disco 18 GB -> 2 GB livres; testar-i1-gpu.sh parou depois do build no checar_disco (só G01 no relatório). Build cache já 0 (o script fez o prune).
- Na placa já existem nvcr.io/nvidia/l4t-tensorrt:r10.3.0-runtime (4.48GB), l4t-cuda:12.6.11-runtime e ods/base-gpu (sem TensorRT).
- Decisão (contorno do P3, sem editar o I1): BASE_IMAGE=nvcr.io/nvidia/l4t-tensorrt:r10.3.0-runtime via build arg (I1_BASE_IMAGE no a8.env; args no compose; --build-arg no teste). Teste agora exige MIN_LIVRE_GB + BUILD_GB (4+4) antes de construir, mostra o tamanho da imagem e faz prune também se o build falhar.
- Validado: bash -n e simulação (build com a base certa, base ausente, pouco disco). Não verificado: se a l4t-tensorrt runtime tem os bindings Python do TensorRT e libcudart (o G02 pega).
- Recado para MOD-1: trocar a base padrão do Dockerfile.jetson para a l4t-tensorrt runtime.

### 2026-11-14 12:14 — teste do I1 na GPU rodou na Jetson
- Resultado (base l4t-tensorrt:r10.3.0-runtime): G01–G05 PASSOU. TensorRT 10.3.0, p2 0.2.0a1, cuda-python 12.6.2.post1, TrtBackend; engine FP16 compilada em 431 s; libnvinfer carregada; GR3D_FREQ até 90%; 8,12 ms/quadro (p95 11,21; 45,7 MB GPU) × CPU ORT 261,26 ms (32×). Disco 18 -> 16 GB livres (imagem ~2 GB + engine).
- Defeito do teste: a base da NVIDIA imprime "== CUDA ==" no stdout; N_IMG e META_JSON ficaram poluídos, a checagem Python quebrou calada e G06–G08 sumiram com "0 falhou".
- Correção: sem_aviso() (docker run --entrypoint "") para ls/cat/test; G02 usa a última linha; checagem das mensagens vira G06 FALHOU se não produzir os 3 itens. Simulado com aviso da NVIDIA e com checagem quebrada.

### 2026-11-14 — A8 de pé após `ods.sh trocar a8`; próximo: `./a8.sh testar` com cam0.mp4
- Feito: o usuário rodou `./ods.sh trocar a8` na Jetson (~2 h: todas as imagens do A8 reconstruídas, porque o trocar anterior para o A6 tinha apagado as imagens; sem cache por causa do `builder prune -af` por etapa).
- Ideia em aberto: `ods.sh trocar --manter-imagens` se o disco aguentar (pedido `df -h /` e `docker system df`).
- Próximo: na Jetson, `./a8.sh status` e `./a8.sh testar` (I7_FONTE=video, P4 toca cam0.mp4, I1 agora na GPU). Se interromper: rodar `./a8.sh testar` de novo (o aceite é recriado com --force-recreate).

### 2026-11-14 17:25 — `./a8.sh testar` com cam0.mp4 na Jetson: resultado esperado
- Resultado: PASSOU 11 (C01–C08, C11–C13), FALHOU 2 (C14 a 94,7 h, C18 published_at do P4), BLOQUEADO 3 (C10, C16, C17), AVISO 2 (C09, C15). Igual à tabela esperada.
- Sessão 460bf576: I1 245, I2 245, S1 245 posições, 9 transições, 9 ocupações, 2 janelas do S5; I7 54 leituras (9 placas); A8 real: OVK7900 liberado, demais negado (nao_cadastrado).
- I1 saiu com "Failed to read from shmsrc / Control socket has closed" no fim do vídeo (conhecido). Avisos NvMap error 12 e Argus no log do I1: a investigar se afetam algo.
- Não provado ainda: GPU dentro da cadeia. O `tegrastats` mostrado só cobre o período depois do teste (0%); o comando do artifact_version falhou porque `dc` é alias no ~/.bashrc da Jetson (`dc() {` dá syntax error).
- A8 decide 6× a mesma placa (uma por quadro lido do I7): recado para VER-5 (deduplicar leituras próximas).
- Arquivos: validacao/a8/evidencias/aceite-a8-20261114-172501.txt; CLAUDE.md seção 5.
- Próximo: usuário roda a prova de GPU (artifact_version do /app/i1-eventos.jsonl do container i1 + grep do backend no log).

### 2026-11-14 — Prova de GPU do I1 na cadeia do A8
- Resultado: a última mensagem do I1 (/app/i1-eventos.jsonl do container) tem artifact_version "app-plates-1.0.0-fp16" → as detecções publicadas vieram do TensorRT (P2_BACKEND=trt impede queda para CPU).
- Problema: às 17:23:01 a criação do contexto TensorRT falhou com OUT_OF_MEMORY (17,6 MB não alocados; Cuda Runtime out of memory; 6 linhas NvMap error 12). O I1 voltou pelo restart on-failure e às 17:23:06 entrou na sessão no frame_index 23. Hipótese: RAM da placa (memória unificada CPU/GPU) cheia com a pilha inteira do A8 + Kafka da turma; quadros iniciais do vídeo podem ter ficado sem detecção.
- Próximo: pedir RestartCount do container i1, free -h e docker stats para medir a memória; decidir contorno (ex.: limitar memória de serviços pesados, como o frontend Expo, ou esperar o I1 carregar antes do P4 tocar).

### 2026-11-14 — Memória da Jetson e contorno no a8.sh testar
- Evidência: Orin Nano Super, 7,4 GiB; free 214 MiB, buff/cache 2,7 GiB, available 2,6 GiB, swap 2,2/3,7 GiB em uso. Containers: kafka (turma) 2,0 GiB, a8-mysql 463 MiB, frontend 207 MiB, s5 134 MiB, resto < 80 MiB. RestartCount do i1 = 2.
- Decisão: `liberar_memoria` no a8.sh (sync + drop_caches via sudo; com terminal pede senha, sem terminal usa sudo -n e só avisa) antes da etapa 3/5 do testar. Simulado aqui com sudo falso (sucesso e falha); bash -n ok; shellcheck não instalado.
- Não mexido: Kafka da turma (maior consumo, de outro grupo). Sugerido ao usuário avaliar desligar a interface gráfica da placa (decisão de P1/usuário).
- Próximo: usuário faz push, roda ./a8.sh testar de novo e confere RestartCount do i1 = 0.

### 2026-11-14 17:43 — 2º `./a8.sh testar` (com liberar_memoria): mesmo resumo, i1 ainda com 2 reinícios
- Resultado: PASSOU 11 FALHOU 2 BLOQUEADO 3 AVISO 2; sessão 5205e9fc: I1/I2/S1 260 (antes 245), 9 transições, 10 ocupações, 8 janelas S5.
- RestartCount do i1 = 2 de novo. Hipótese nova: nem todo reinício é OOM; o I1 sai com código 1 no fim do vídeo ("Control socket has closed") e o restart on-failure o religa, o que também conta. Pedida linha do tempo do log (com timestamps) e a saída do liberar_memoria.

### 2026-11-14 — Linha do tempo do I1 no 2º teste: memória resolvida, sobrou a corrida com o P4
- liberar_memoria: ~500 MB → ~2000 MB livres; nenhum OUT_OF_MEMORY no log.
- Reinício 1 (17:41:38): "Não foi possível iniciar a pipeline P4" — o I1 partiu antes do P4 criar /tmp/p4_file_shm (depends_on service_started não garante o socket). Entrou na sessão às 17:41:41.
- Reinício 2 (17:42:07): fim do vídeo, "Control socket has closed", código 1 (pendência MOD-1, conhecida).
- Contorno no compose do A8: comando do i1 via sh espera o socket (até 60 s) e faz exec do run_detector. Testado aqui com sh e socket unix real (com e sem socket). Sem docker compose local (daemon sem permissão), então `config` não foi rodado. Não muda o hash da receita (só o "build" entra): sem rebuild.
- Próximo: push; na Jetson `./a8.sh testar` e linha do tempo do log; esperado RestartCount 1 (só o do fim do vídeo).

### 2026-11-14 17:58 — 3º `./a8.sh testar`: contornos do I1 confirmados na Jetson
- Resultado: PASSOU 11 FALHOU 2 BLOQUEADO 3 AVISO 2 (igual ao esperado). Sessão 44bc90e2: I1/I2/S1 234, 9 transições, 10 ocupações, 7 janelas S5, 54 leituras I7.
- i1: RestartCount 1 (só o do fim do vídeo); sem OUT_OF_MEMORY, sem falha de partida. Contornos a647563 (drop_caches) e e242f16 (espera do socket) validados na placa.
- Detecções por sessão variam entre execuções (245, 260, 234): anotado, não investigado.
- Arquivos: validacao/a8/evidencias/aceite-a8-20261114-175800.txt; CLAUDE.md (seção 5 e VER-5: decisão repetida por leitura).
- Próximo: propor tag a8-cadeia-v2 (cadeia com I1 na GPU) ao usuário; depois levar o I1 GPU para A3/A4/A5 ou validar A2 na Jetson.

### 2026-11-14 — Teste de tempo real do I1 (pedido antes de marcar a tag)
- Levantamento: o repo do I1 (cb5c381) só tem testes unitários com mock (I1/tests; latência 6,45 ms fixa no MockP2Backend). O run_detector lê MP4 direto (OpenCV, sem ritmo) e imprime a inferência média; cada mensagem tem captured_at e published_at, e o jsonl é aberto com "w".
- Feito: validacao/i1/testar-i1-tempo-real.sh (R01–R06) + seção no README. Parte 1: I1 no cam0.mp4 o mais rápido possível → tempo total, vazão, tempo por quadro, folga sobre o fps alvo. Parte 2: /app/i1-eventos.jsonl do container i1 do ods-a8 → atraso P4→I1 e quadros perdidos.
- Validado só aqui: bash -n e simulação (docker/tegrastats/sudo falsos), casos "acompanha", "não acompanha" e cadeia com quadro perdido. Corrigida a colisão da variável N (cor) com a contagem de mensagens.
- Próximo: usuário roda na Jetson logo depois de um ./a8.sh testar (para a parte 2 ter dados).

### 2026-11-14 15:14 — 1ª execução do testar-i1-tempo-real.sh na Jetson: R01 falso negativo
- Resultado: "nenhuma engine em /var/lib/ods/engines", mas a engine existe (o A8 usou). Causa: o p2-build cria a pasta com tempfile.mkdtemp (0700, dona root, src/p2/build/output.py); o usuário ods não lista o conteúdo, e o glob do host falhou.
- Correção: a conferência da engine roda dentro de um container (root), como o I1. Simulado (com e sem engine). Recado no CLAUDE.md seção 8 (SIS-1/P2).
- Próximo: usuário roda de novo na Jetson (depois de um ./a8.sh testar, para a parte 2).

### 2026-11-14 15:18 — testar-i1-tempo-real.sh na Jetson (parte 1, pelos logs enviados)
- i1.log: 270 quadros 1280x720, código 0, todos -fp16, 270 detecções; inferência média 24,97 ms (o G04 isolado deu 8,1 ms).
- Pelos timestamps: 1º quadro 212 ms (aquecimento); depois ~32 ms da leitura à publicação e um quadro a cada ~39–40 ms → vazão ~25 quadros/s; 270 quadros em ~10,8 s.
- tegrastats: GPU parada de 15:17:48 a 15:18:04 (~16 s para subir o container e carregar a engine); GR3D 35–99% durante o processamento; CPUs entre 729 e 883 MHz, um núcleo em ~56–60% (thread Python).
- Conclusão provisória: acompanha câmera de 10 quadros/s (~2,5×); não acompanha 30 quadros/s (~25). Hipótese para a inferência 3× mais lenta que o probe: relógios baixos (modo de energia/jetson_clocks) e custo de CPU no I1. Pedido: relatório .txt (fps do vídeo e parte 2) e `nvpmodel -q` / `jetson_clocks --show`.

### 2026-11-14 15:20 — Relatório R01–R05 (alvo 30) e modo de energia
- Relatório i1-tempo-real-2026-11-14-151742 (--fps-alvo 30 --sem-cadeia): vídeo 270 quadros a 10 fps = 27 s; total 27,9 s = 17,1 s de partida + 10,82 s; 25,0 quadros/s; p50 32 ms, p95 33 ms, máx 212 ms; inferência 24,97 ms. R04 FALHOU para 30 fps (0,8×); para 10 fps a folga é 2,5×.
- Energia: nvpmodel 25W (modo 1), governor schedutil, CPU 729–1728 MHz, GPU 306–1020 MHz (estava em 306 MHz parada), EMC 665/3199 MHz. Hipótese: relógios dinâmicos não sobem com a carga intercalada CPU/GPU do I1 (o probe G04, 300 infer seguidos, deu 8 ms).
- Proposto ao usuário: teste A/B com `jetson_clocks` (guardar com --store, restaurar com --restore). Decisão dele (placa compartilhada). Falta o relatório da 1ª execução (alvo 10, com a parte 2 da cadeia).

### 2026-11-14 15:27 — Teste A/B com jetson_clocks e parte 2 da cadeia
- jetson_clocks (store/restore feito pelo usuário): 64,3 quadros/s, 11 ms por quadro, inferência 8,33 ms, GR3D até 53% (agora o limite é a CPU). Sem: 25 quadros/s, 32 ms, 24,9 ms.
- Parte 2 (cadeia, sessão 44bc90e2): 234 publicados, frame_index 35–269; atraso P4→I1 mediana 34 ms; 1 perdido no meio, 35 no começo (I1 carregando a engine enquanto o P4 já toca). Explica a variação 245/260/234 entre testes.
- Defeito do script: R05 errado por locale pt_BR (awk printf "100,0" comparado como texto). Corrigido nos dois scripts (LC_NUMERIC=C). Simulação local não reproduz o locale (pt_BR não instalado aqui).
- Arquivos: validacao/i1/evidencias/i1-tempo-real-2026-11-14.txt; README; CLAUDE.md (lição + pendências SIS-1 e MOD-1).
- Próximo: tags (a8-cadeia-v2 e conferir a8-cadeia-v1) com o usuário.

### 2026-11-14 15:45 — Teste de resistência do jetson_clocks (antes da decisão do usuário)
- Pedido: o usuário quer saber se a placa aguenta jetson_clocks o tempo todo antes de decidir.
- Feito: validacao/placa/testar-jetson-clocks.sh + README. Fases base / parado / carga contínua (sonda p2.infer sem pausa, relatório a cada 30 s); tegrastats e ventoinha por fase; J01 temperatura vs. 1º trip passivo (folga ≥ 10 °C), J02 contadores oc*_event_cnt, J03 inferências/s último ≥ 90% do primeiro trecho, J04 Kafka de pé, J05 custo parado. Restaura com --restore no EXIT/INT/TERM.
- Simulado aqui (fakes + TERMICO falso): normal, quente com queda e sem Kafka, interrompido na fase 2 (restaurou). Corrigido: laço que mantém o sudo segurava o pipe (saída agora em /dev/null).
- Próximo: usuário roda na Jetson (~40 min) e decide; depois, tags.

### 2026-11-14 16:00 — Testes do próprio repositório do I1; regra: I1 sempre na develop
- Usuário: "Use sempre develop como branch base para i1". Registrado na memória, no CLAUDE.md (seção 2 e pendência MOD-1 sem "merge na main") e no comentário do a8.env. HEAD da origin/develop = cb5c381 (já é o fixado).
- Testes do I1 (cb5c381): 5 suítes unittest em I1/tests (contrato/schema B1, tratamento de erros, sessão e sequência, ingestão P4, auditoria sprint 3) + CI .github/workflows/i1-tests.yml (ubuntu, CPU). Estão dentro da imagem Jetson (COPY I1/, schemas/ copiado, .dockerignore não exclui).
- Rodado aqui (venv Python 3.10 com os mesmos pacotes da imagem, sem p2/TensorRT): 40 testes, 39 ok, 1 erro: test_05_t16 (Degrau A com ONNX real) importa ultralytics, que a imagem Jetson não tem. Nenhum teste deles usa a GPU de verdade: o P2 é sempre simulado (FakeP2Module/MockP2Backend).
- Próximo: usuário roda a suíte dentro de ods-i1-gpu:cb5c381 na Jetson e manda a saída.

### 2026-11-14 16:05 — testar-i1-servico.sh (testes do I1 no serviço exato da build)
- Pedido: rodar os testes do I1 no "exato serviço da Jetson". `docker compose run i1` não serve (ipc: service:p4 exige o P4 rodando); o script lê o serviço i1 do `docker compose config` do builds/a8 e roda `docker run` com a mesma imagem, runtime, env e volumes (sem ipc e /tmp do P4).
- Itens: S01 imagem = I1_REF; S02 suíte I1/tests (aceita só o erro do test_05/ultralytics); S03 CMD padrão da imagem (fixtures, backend p2): código 0, mensagens, -fp16.
- Simulado com docker falso (esperado, outra falha, tudo ok). Corrigidos: contagem do unittest pelo resumo final (as linhas "... ok" se misturam com os logs) e grep sem resultado sob set -e.
- Próximo: usuário roda na Jetson.

### 2026-11-14 16:03 — testar-i1-servico.sh na Jetson: 3 PASSOU
- S01 imagem cb5c381 (2,1 GB); S02 39/40 (só test_05, ultralytics); S03 CMD padrão: código 0, 9 mensagens, 9 detecções, -fp16.
- Arquivos: validacao/i1/evidencias/i1-servico-2026-11-14.txt; README; CLAUDE.md seção 6.
- Próximo: decisão do usuário sobre o sinal verde ao MOD-1 (texto revisto: sem merge na main, + test_05 pular sem ultralytics); teste de resistência do jetson_clocks; tags.

### 2026-11-17 — análise: qual aplicação está mais completa para subir
- Pedido do usuário: com base no feito e nas atualizações recentes dos repos da turma, qual app subir agora.
- Feito: pushed_at da org (atividade desde 13/11: i6, a2 [17/11], b1, i4, i7, s2, a7, i5, s3, i1, a6, s4); clones bare em scratchpad/repos para comparar com os commits fixados.
- Resultado (17/11): commits novos desde os fixados: A2 main 19ead4e (develop fundida hoje; web-app com Dockerfile próprio, porta 8080, painel de telemetria; núcleo A2Local quase igual; web-app ainda com AES b"a"*32 e SQLite dentro da imagem); I6 main 86ae5d7 = develop ff1bf44 (sem mudança de código); I7 main ff9d759 (detector_p2.py, modelo app-plates no repo, broker da Jetson); I1 develop cb5c381 já fixado; S4 2324858/298e3de (registry e broker revertido p/ 34.66.235.91 — conferir se é só padrão); I5 ganhou Dockerfile/Dockerfile.jetson (A7 ainda sem); A6 5ad584c (qwen3-frases-deploy); I4 503f64b (docker); S3 1a322c4 "S3 na nuvem"; S2 develop 7c0e841 (testes, segue sem Kafka); B1 só dependabot.
- Conclusão: mais completa = A8 (única validada na placa, cadeia inteira). Próxima nova = A2 (main fundida hoje, Dockerfiles do time, 3 componentes, sem GPU). A3/A4/A5/A1/A6/A7 seguem bloqueadas por S2, falta de Dockerfile, modelos ou P5/P7.
- Próximo: aguardar o usuário — sugerido refixar A2 na main 19ead4e (e usar o Dockerfile do web-app) e conferir I7 ff9d759 / S4 298e3de no A8.

### 2026-11-17 — preparar A2 (pedido do usuário: "vamos preparar as coisas para a2")
- Levantamento a2 main 19ead4e: A2Local só ganhou utils/payload.py (chave fixa, não usado pelo liberar.py); web-app com Dockerfile multiestágio (node:20-alpine → python:3.12-slim, PORT 8080, HEALTHCHECK /admin); .dockerignore tira o db.db da imagem; DB_PATH fixo em backend/db/db.db (mesma pasta de connection.py → volume ali congelaria o código); ACCESS_EVENT_KEY gerada e gravada em /app/.env se não vier do ambiente; admin padrão admin/admin123; rota /access-event existe mas nada no A2 a chama (painel sem dados); AES do web-app segue b"a"*32.
- I6 main 86ae5d7: mesma árvore de ff1bf44 → fixar na main (sem custo, A2 nunca foi construído na placa).
- S4: novos commits só mudam o broker padrão e build/registry → manter be0cad9 (validado no A8, imagem já na placa).
- Plano: a2.env (A2 19ead4e, I6 86ae5d7); compose a2-cracha com o Dockerfile do VER-2 + volume a2-cracha-dados em /dados e symlink do db.db; ACCESS_EVENT_KEY opcional nos segredos; validar-a2-fluxo.sh com rotas novas; README/LEIA-ME/CLAUDE.md.
- Feito: a2.env (A2 19ead4e main, I6 86ae5d7 main, S4 mantido be0cad9); compose a2-cracha com Dockerfile do VER-2, entrypoint sh -c "ln -sf /dados/db.db /app/backend/db/db.db && exec python main.py", volume a2-cracha-dados, ACCESS_EVENT_KEY=${A2_ACCESS_EVENT_KEY:-}; secrets.exemplo (chave opcional + aviso admin/admin123); a2.sh confere /app/ e /admin; limpar.sh com backup do web-app; validar-a2-fluxo.sh com rotas do web-app (401 sem login/chave, aviso se admin123 ainda vale, com logout); READMEs; pendência VER-2 no CLAUDE.md.
- Validado (fora da Jetson): bash -n nos 3 scripts; YAML e variáveis do compose (pyyaml); COPY do Dockerfile do web-app existem no 19ead4e; SQLite por link → db, -wal e -shm no destino, reabre com dados. NÃO validado: docker compose config (sem plugin local), shellcheck (ausente), build da imagem (sem acesso ao docker aqui).
- Próximo: commit (se o usuário pedir); na Jetson: git pull; cp a2.secrets.env.exemplo a2.secrets.env (A2_AES_KEY = 32 "a"); vídeo /var/lib/ods/videos/portaria.mp4 com QR; ./ods.sh trocar a2; validar-sistema.sh a2; validar-a2-fluxo.sh; ./a2.sh testar.

### 2026-11-17 — troca de foco: A5 (decisão do usuário)
- Usuário: "Vamos com A5. Rodar a2 seria meio difícil por algumas questões." O A2 fica preparado (alterações locais, sem commit) e sai de foco.
- Próximo: levantar o estado do A5 (build de 13/11) contra os repos atuais (a5, i9, i1, i2, i3, s1, s3, s4, s2).
- Levantamento A5 (17/11): a5 main c634433 (sem commits novos), i9 main 8ae3933 (idem), i2/s1/p4 iguais ao A8; s3 main 1a322c4 só docs/instalador (pode subir); s2 develop 7c0e841 segue SEM Kafka (C09 continua bloqueado).
- ACHADO: a develop do I1 (cb5c381, a mesma do A8 em GPU) traz I1/artifacts/app-epi/1.0.0 (ONNX 44 MB, classes pessoa/capacete/colete, mAP50 0,95; B5 publicou em 20/10). O I9 (config/policy.json) usa exatamente essas classes. → A5 pode ter detecção REAL de EPI na GPU (antes: modelo de placas só p/ transporte). CLAUDE.md (pendência MOD-1/B5 "sem modelo de EPI") está desatualizado.
- I9 sem I3: segue, só marca o estado da calibração. P4: source_id = file_<stem do arquivo> → vídeo de EPI próprio (ex.: epi.mp4 → file_epi); cam0.mp4 é de estacionamento, não serve para EPI.
- Plano: A5 com I1 GPU igual ao A8 (Dockerfile.jetson, l4t-tensorrt, i1-engine, I1_PACOTE=app-epi/1.0.0), VIDEO_ARQUIVO configurável, zonas e aceite pelo source_id do vídeo, C10 passa a medir detecção real; a5.sh com checar_gpu/pasta de engines/liberar_memoria/preparar_engine.
- Feito (A5, 17/11): a5.env (S3 1a322c4, I1 develop cb5c381 em GPU, I1_PACOTE=app-epi/1.0.0, I1_ENGINES_DIR, I1_BASE_IMAGE, VIDEO_ARQUIVO=epi.mp4, VIDEO_SOURCE_ID=file_epi; sem MODELOS_DIR/I1_ONNX); compose: i1 = I1 GPU do A8 + i1-engine, p4/s4 com VIDEO_ARQUIVO, p4 espera i1-engine, aceite com VIDEO_SOURCE_ID/I1_PACOTE; zonas com file_epi; a5.sh com checar_gpu, pasta de engines, preparar_engine_i1 (no pos_subida), liberar_memoria, tocar_video, coerência VIDEO_ARQUIVO↔VIDEO_SOURCE_ID↔zonas; testar = itens simulados → espera "passo externo 'video'" → vídeo → passo → restart s4; aceite_a5.py: C10 detecção real (exige app-epi-1.0.0-fp16 + pessoa), C12 I9 no vídeo, C13 I2→S1, amostra de 50 msgs reais por tópico no contrato; docs (README builds/validacao, relatório, CLAUDE.md MOD-1/B5 e nota A3/A4/A5).
- Validado (fora da Jetson): bash -n; py_compile + pyflakes (limpo); YAML/variáveis do compose; commits fixados existem; Dockerfile.jetson copia I1/ (app-epi entra na imagem); aceite contra Kafka/API falsos (scratchpad/sim-a5): ok → 11 PASSOU; cpu → C10 FALHOU; sem_pessoa → C10/C12 AVISO; sem_i9 → C12 FALHOU; sem_video → C10/C12/C13 BLOQUEADO. NÃO validado: docker compose config, shellcheck, execução na placa.
- Pendente com o usuário: vídeo de EPI (/var/lib/ods/videos/epi.mp4, pessoas com/sem capacete e colete, H.264, ~1280x720); commit.

### 2026-11-17 — commit do A5
- Commit c8d41dc (local, sem push): builds/a5, validacao/a5, linhas do A5 no CLAUDE.md e builds/README.md, este arquivo. Alterações do A2 seguem só no disco.
- Limpeza: na 1ª tentativa de clonar (scratchpad inexistente) 6 clones --bare (a5 b5 i2 i9 p4 s1, ~320 MB) caíram em builds/a5/; removidos antes do commit.
- Próximo: git push (se o usuário pedir); na Jetson, git pull e o roteiro do Estado atual.

### 2026-11-17 — A5 na Jetson: "/health" pelo nginx com HTTP 502 no pos_subida
- Usuário trouxe: "! API do A5 (pelo nginx) ainda não respondeu em http://127.0.0.1:8095/health (HTTP 502)".
- Causa provável (código a5 c634433): lifespan roda PublicacaoService().sincronizar() antes do yield; RULES -> S2 espera reply 2 × 10 s (S2 sem Kafka) → backend fica ~20 s sem abrir a 8000 a cada partida (rules-a5 nunca é registrado). Nosso compose não tinha healthcheck → esperar_servicos aceitou "running" → nginx 502.
- Feito: healthcheck de porta no a5-backend (igual ao do VER-3; interval 5s, start_period 90s) e a5-frontend depends_on service_healthy. YAML conferido localmente. Sem commit ainda.
- Recado VER-3: não bloquear a partida esperando reply do S2 (mover o sincronizar para depois do yield/thread).
- Próximo: usuário confirmar na placa (logs do a5-backend, curl /health) e repetir ./a5.sh subir.

### 2026-11-17 — A5 na Jetson: a5-backend "unhealthy" (com o healthcheck novo)
- Saída do usuário: I1 GPU construído (ods-i1-gpu:cb5c381), disco 10 GB livres; up: kafka-topicos Exited em 72,1 s (lento!), s3/s4 Started ~93 s, a5-backend "dependency failed to start: unhealthy" em 95,9 s, frontend Running.
- Hipótese: partida do backend > 90 s com o Kafka da turma lento: _garantir_escuta até 15 s, flush(10) por artefato publicado (ZONES por câmera, PPE_CATALOG, ROUTING), RULES -> S2 2 × 10 s. Outra possibilidade: erro na partida (crash/loop).
- Pedido ao usuário: estado + Health do container, logs do backend, tempo de resposta do broker. NÃO mexer no compose antes de ver os logs.
- RESULTADO (logs do usuário): NÃO era Kafka (broker respondeu em 3,9 s). a5-backend em laço (11 reinícios): "ValueError: A senha precisa de pelo menos 4 caracteres." (auth/service.py:_definir_senha; única regra). A5_ADMIN_SENHA da placa tem < 4 caracteres. O 502 anterior provavelmente era o mesmo erro (a hipótese do S2 explica só ~20 s de partida; healthcheck mantido).
- Feito: a5.sh checar_entradas para com erro claro se A5_ADMIN_SENHA < 4; a5.secrets.env.exemplo documenta a regra. bash -n ok; checagem simulada (3 → erro, 4 → ok).
- Próximo: usuário corrigir a senha na placa e "dc up -d" (ou ./a5.sh subir); commit desta checagem.
- Jetson (17/11): com senha de 4+ caracteres o a5-backend ficou "healthy" (partida ~70 s junto com kafka-topicos). Restou 502 no :8095/health: o frontend (Up 40 min) não foi recriado; o nginx do VER-3 resolve "backend" só ao subir e guardou o IP do container velho. Solução imediata: dc restart a5-frontend.
- Feito: a5.sh pos_subida reinicia o a5-frontend se ele começou antes do backend atual (StartedAt). bash -n ok. Sem commit (junto com a checagem da senha).
- Obs.: o usuário usou o alias "dc" do ~/.bashrc (aponta para a8.env) → "couldn't find env file a8.env"; redefinir o alias na pasta do A5 ou usar ./a5.sh.
- Jetson: após dc restart a5-frontend o curl imediato deu 000 (nginx ainda reiniciando, 1,1 s). a5.sh agora espera o front responder (até 15 s) depois do restart. Pedido: repetir o curl com sleep 3.
- Jetson (17/11): após o restart do front, curl http://127.0.0.1:8095/health → 200. A5 DE PÉ na placa (a5-backend healthy, a5-frontend, s3, s4). Falta: vídeo epi.mp4 e ./a5.sh testar.

### 2026-11-17 — A5 testar: compilação da engine app-epi com "NvMap ... error 12"
- Saída do usuário: i1-engine compilando app-epi-1.0.0 (FP16; ENGINE_NOT_FOUND na 1ª vez) e dezenas de "NvMapMemAllocInternalTagged: 1075072515 error 12" (ENOMEM da GPU; mesma família do OUT_OF_MEMORY do A8 em 14/11). Resultado final ainda não visto (pode terminar: o TensorRT pula táticas sem memória).
- Causa no P3: a5.sh só fazia drop_caches antes do vídeo, não antes de compilar a engine (pos_subida/testar com a pilha toda de pé).
- Feito: preparar_engine_i1 chama liberar_memoria quando a pasta da engine (I1_ENGINES_DIR/app-epi-1.0.0) não existe. bash -n ok. Sem commit.
- Pedido ao usuário: deixar terminar; se falhar, drop_caches e ./a5.sh testar de novo; trazer o fim da saída.
- Commit ecf8147: liberar_memoria antes de compilar a engine.

### 2026-11-18 — 1º ./a5.sh testar completo na Jetson (aceite-a5-20261118-022008)
- PASSOU 7, FALHOU 4 (C03, C06, C07, C11), BLOQUEADO 1 (C09), AVISO 1 (C04).
- C10 PASSOU: 95 quadros do I1 na GPU, artifact_version app-epi-1.0.0-fp16, classes pessoa/capacete/colete. C12: 95 avaliações do I9. Cadeia real P4 -> I1 (GPU, EPI) -> I9 / I2 -> S1 funcionando.
- A investigar: C03 (S4 sem clipe), C06/C07 (S3 recusa ACK: "UNAUTHORIZED_ACTOR user:administrador"), C08/C12 com estados {} (o I9 publica persons[].equipment[].state, o teste lia items[].compliance → defeito do TESTE), C13 transições 0 (I2 rastreia "pessoa"?), C11 (I9 fora do contrato 1.0: payload por quadro com persons[]; session.started do P4 com occurred_at, já conhecido).
- Análise (18/11):
  - C06/C07 = falha da COMPOSIÇÃO (P3): a imagem do S3 usa /config/permissoes.json de exemplo do contrato (só user:maria/user:joao); o A5 gera o arquivo certo em GET /integracoes/s3/permissoes, mas a build não ligava. E o arquivo do A5 cru é RECUSADO pelo validador do S3 ("role:operador não está em members": o A5 só põe em members papéis com usuários) — conferido com o código real do S3 (s3/permissoes.py). Recado VER-3.
  - C08/C12 com {} = defeito do TESTE: o I9 publica payload.persons[].equipment[].{equipment_item,state}; o teste lia items[].compliance.
  - C11: I9 fora do contrato 1.0 (6c: um evento por pessoa com detection_id/bbox/calibrated/items; o I9 publica por quadro com persons[]) → recado VER-3/I9; session.started do P4 com occurred_at (já conhecido, C18 do A8).
  - C13: o teste só contava mensagens; transições 0 sugere trilhas vazias. I2 não filtra classes (pessoa usa o perfil padrão). Aguardando dados da placa.
  - C03: S4 tem handler de ods.s2.event e loga o motivo quando não grava (sem buffer/relógio). Aguardando log do S4.
- Feito: config/permissoes-s3.exemplo.json (validado com o código do S3: admin ACK/CLOSE ok); compose monta ./estado/permissoes-s3.json em /config/permissoes.json:ro; a5.sh garantir_permissoes_s3 (antes do up) e atualizar_permissoes_s3 (pos_subida e início do testar: baixa do A5, normaliza, regrava no mesmo inode, reinicia S3 se mudou); .gitignore builds/*/estado/; aceite: estados_epi (persons/equipment), C08 FALHOU se sem equipamento, C12 AVISO idem, C13 exige trilhas/posições com conteúdo, extras com resolução e amostras reais. py_compile/pyflakes/bash -n ok; simulador atualizado (formato real do I9): 6 cenários ok. Sem commit.
- Na placa: precisa ./a5.sh subir (recria o S3 com o volume novo) antes do testar.

### 2026-11-18 13:30 — aceite-a5-20261118-131217 (Jetson)
- Resultado: PASSOU 9, FALHOU 2, BLOQUEADO 1, AVISO 1. C06/C07 passaram (permissões do S3 vindas do A5, commit 5a17aeb). C08/C12 com o parser novo: I9 real avaliou 102 quadros, capacete INCORRETO 102, colete INCORRETO 101 (no quadro 83 o capacete está na parte de baixo da caixa da pessoa: placement_score 0,12, v 0,22).
- C13: 100 posições, todas com zone_ids vazio. Vídeo 1920x1080, zona 0..1280x0..720 (ex.: ponto 848,1075 fora).
- Feito: zona renomeada para artefatos/zones-a5-p3-2.json em 1920x1080 (compose, a5.sh, a5.env); C13 agora só PASSOU com ponto na zona e transição, AVISO cita a resolução; resolução calculada antes do C13. py_compile, pyflakes, bash -n ok; regra testada com as posições reais do relatório.
- Tempo real (pergunta do usuário): P4 tem modo câmera (IMX519/477 1080p RG10) e o I1 lê /tmp/p4_imx519_shm; o que impede alertas reais é o S2 fora do Kafka (A5 ← ods.s3.alert ← ods.s2.event); S4 com câmera esbarra no P4R1 × NV12.
- C03: S4 registra o motivo (S2 event ignored / no capture buffer / buffer clock not started / clip failed) — falta o log.
- Próximo: commit quando o usuário pedir; rodar de novo na placa.

### 2026-11-18 — por que o S2 não sobe no A5 (pergunta do usuário)
- Conferido na develop do s2 (274ce5b, 18/11): ganhou Dockerfile (python:3.11-slim, entrypoint components.S2.main), mas segue lendo `--input` JSON e gravando `--output` JSON; requirements só shapely/pytest; README: "Integração com o barramento Kafka" pendente.
- Novo achado: o S2 espera o I9 no formato da 6c (payload.detection_id + items[].compliance, ex.: gerar_teste_ppe.py), e o I9 real publica persons[].equipment[].state (CORRETO/INCORRETO). Mesmo com Kafka, os dois não se entendem: recado para VER-3 (I9) e VER-6 (S2).

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
