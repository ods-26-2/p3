# Progresso — builds ODS (P3)

## Estado atual
- Aplicação em foco: A8 com I1 na GPU (TensorRT via P2), depois A1–A7
- Fase: I1 em GPU escrito e commitado (687e0fb); A1–A7 escritos; nada disso rodado na Jetson
- Último resultado: testar-i1-gpu.sh ok contra docker/tegrastats simulados (sucesso, queda p/ CPU, sem runtime nvidia); compose do A8 checado só por YAML/variáveis
- Próximo passo: na Jetson: git pull; df -h /; cd validacao/i1 && ./testar-i1-gpu.sh; depois cd builds/a8 && ./a8.sh subir && ./a8.sh testar. Se passar: levar o I1 em GPU para A3/A4/A5. Depois: A1–A7 por app (./ods.sh trocar <app> -> validar-sistema.sh -> validar-<app>-fluxo.sh -> ./<app>.sh testar), começando pelo A2.
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
