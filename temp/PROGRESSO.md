# Progresso — builds ODS (P3)

## Estado atual
- Aplicação em foco: A8 com I1 na GPU (TensorRT via P2), depois A1–A7
- Fase: I1 em GPU VALIDADO na Jetson (14/11: G01–G05 passaram, 8,1 ms GPU × 261 ms CPU); G06–G08 não rodaram por defeito do teste (aviso da NVIDIA no stdout), corrigido; falta rodar o teste de novo e subir o A8
- Último resultado: testar-i1-gpu.sh ok contra docker/tegrastats simulados (sucesso, queda p/ CPU, sem runtime nvidia); compose do A8 checado só por YAML/variáveis
- Próximo passo: na Jetson: git pull; cd validacao/i1 && ./testar-i1-gpu.sh (rápido: imagem e engine já existem); copiar o relatório para validacao/i1/evidencias/; depois cd builds/a8 && ./a8.sh subir && ./a8.sh testar. Se passar: levar o I1 em GPU para A3/A4/A5. Depois: A1–A7 por app (./ods.sh trocar <app> -> validar-sistema.sh -> validar-<app>-fluxo.sh -> ./<app>.sh testar), começando pelo A2.
- Bloqueios / perguntas abertas ao usuário: docker compose config e shellcheck não rodados localmente; tag a8-cadeia-v1 a confirmar; espaço em disco para a base l4t-jetpack r36.4.0 (vários GB)
- Continuidade: este arquivo e o CLAUDE.md foram versionados a pedido do usuário (13/11/2026) para continuar em outro computador; temp/ segue no .gitignore (PROGRESSO.md entrou com git add -f).

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
