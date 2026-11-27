# Situação dos componentes da build `inf` (P3 · SIS-1)

**Atualizado em 27/11/2026.** Commits conferidos nesse dia contra a ponta de cada repositório
(`git ls-remote`).

A build `inf` reúne todas as inferências da Jetson. Desde 27/11 ela roda sobre as builds das
aplicações da nuvem:

| Build | O que sobe |
|---|---|
| `inf_a4` | I1 + I2 |
| `inf_a1` | I8 |
| `inf_a2` | I6 |
| `inf_a8` | I7 |
| `inf` | I9 contínuo e I3 sob demanda |

O comando `./ods.sh trocar inf` sobe as cinco. O I4 e o I5 estão fora da build, por decisão do
usuário.

**Branch usada.** Vale a branch com o código mais apto, não necessariamente a `main` (regra do
usuário, 27/11/2026). Conferido em 27/11 com `git rev-list` contra todas as branches de cada repo:

- **I1:** `develop` (a `main` só tem merges antigos);
- **I7:** `development` `9e24056`, que contém toda a `main`;
- **I2, I3, I4, I5, I9:** só têm `main`;
- **I6:** `main` (a `develop` está 6 commits atrás);
- **I8:** `main` (a `develop` e a `Feature-i8-similiaridade`, de 3 e 4/11, divergiram antes da sprint 3
  e apagam o `validacao-local`).

**Onde cada resultado foi obtido.** Ao lado de cada resultado está o lugar em que ele foi medido:

- **Jetson:** na placa, com a data;
- **notebook:** suíte rodada em venv no computador do P3, sem GPU;
- **simulação:** scripts do P3 contra um `docker` falso.

## 1. Tabela geral

Legenda da coluna "Sobe?": **sim** = subiu na placa no arranjo indicado; **não testado** = imagem ou
build ainda não rodada na placa; **fora** = fora da build por decisão do usuário.

| Componente | Onde / modo | Commit | Sobe? | Testes automatizados | Passam? | Pendência das equipes que impede subir ou atender o A da nuvem | Solução sugerida |
|---|---|---|---|---|---|---|---|
| **I1** detecção (MOD-1) | `inf_a4`, orquestrador contínuo na GPU; atende por pedido (`ods.i1.command`) | develop `3b2a9cc` (sem mudança) | **sim** (Jetson 25/11 e 27/11, Kafka da nuvem) | `I1/tests` + CMD da imagem (`validacao/i1/testar-i1-servico.sh`); aceite `inf_a4` (T-I1…) | 45/46 (Jetson 24/11). **Falha esperada:** `test_05` precisa do `ultralytics`, que a imagem da Jetson não leva (usa TensorRT). Aceite `inf_a4` 10/10 (25/11) | **Não impede subir.** Impede atender bem: (a) **um modelo por vez**, e só o A4 pede o I1. O A5 (I9 → S2 → S3) e o A3 (I2 → S1 → S2) precisam de detecções VER3/VER6 contínuas, e ninguém manda `START` para elas; (b) o `INV1.mp4` tem 32 s: a sessão acaba, e os `HEARTBEAT` do A4 passam a ser ignorados; (c) `ods.i1.command` sem contrato na 6c/B1 | (a) MOD-1: permitir mais de uma equipe (dois contextos TensorRT, ou fatias de tempo), e VER-3/VER-6 mandarem `START`/`HEARTBEAT` como o A4; (b) o A4 reenviar `START` a cada 20 s (o orquestrador já renova o lease) ou o I1 tocar o vídeo em laço. Com o P4 `2b136d1` (MP4 em laço), `"source": "video"` daria fluxo contínuo, mas com `source_id` `file_INV1`; (c) B1 publicar o schema do comando |
| **I2** rastreio (INV-1) | `inf_a4`, contínuo | `5f4957c` (sem mudança) | **sim** (Jetson 25/11, 27/11) | `I2/tests` (unittest) | 35/35 (Jetson 24/11) | Nenhuma | — |
| **I3** calibração (INV-1) | `inf`, **sob demanda** (artefato: publica uma vez por câmera e versão) | `0a7f944` (sem mudança) | **sim** (Jetson 27/11, T-I3) | `I3/tests` (unittest); T-I3 do aceite | 33/33 (Jetson 24/11); T-I3 PASSOU (27/11) | **Não impede subir.** O A5 (`fe2b9a1`, 27/11) agora lê `ods.i3.calibration` por câmera. Ninguém publicou a calibração das câmeras do A5: as zonas dele vão em pixels | VER-3 enviar as correspondências (ou a imagem do piso) das câmeras do A5 com o `source_id` delas; o P3 roda o I3 com `--source-id`/`--versao` dessas câmeras |
| **I4** Libras (INV-2) | **fora** (comentado no compose) | `503f64b` → `d6a2185` (27/11: modelo final, `--min-confidence`, `ao_vivo_local.py`) | **fora**. O `503f64b` subiu na placa em 24/11; o `d6a2185` não foi construído | `tests/` (pytest) | 74/77 com o `503f64b` (Jetson 24/11). **Falha esperada:** os 3 testes de parquet falham, porque o `pyarrow` 26 exige numpy 2. O `requirements-i4.txt` não mudou no `d6a2185`, então a falha continua | (a) `pyarrow>=15` sem teto (com `numpy<2`) e `mediapipe>=0.10.14` sem versão fixa; (b) o A6 precisa de sinais contínuos, mas o ao vivo só recebe quadros de uma webcam pelo websocket (`webcam.py`). O `ao_vivo_local.py` só abre câmera por índice ou URL `http/rtsp`, não arquivo; (c) repo `s6` vazio (o S6 está em `i4/s6_synthesis`) | (a) INV-2: fixar `pyarrow==17.0.0` (como no S6) e a versão do `mediapipe`; (b) aceitar caminho de arquivo no `ao_vivo_local.py` (o `cv2.VideoCapture` já abre), ou o P3 manter o `i4-video` em laço como fonte; (c) mover o S6 para o repo `s6` |
| **I5** fala (VER-4) | **fora** | `d7b1379` → `aabe73b` (27/11) | **fora**; o `aabe73b` não foi construído | `tests/` (pytest, 34) | 30/34 (**notebook** 27/11, Python 3.10, sem torch, como a imagem da Jetson). **Falhas:** 2 testes de VAD (sem torch, o Silero não carrega e o VAD cai para energia: a imagem da Jetson roda **sem Silero**) e 2 de `captured_at`, que pedem `librosa`, ausente dos requirements | (a) **P5 sem serviço**: o I5 lê o áudio por memória compartilhada (`/dev/shm/jetson_audio_stream_raw`), e o repo `p5` só tem um script de gravação, sem memória compartilhada nem Kafka; (b) engines `whisper-small-encoder/decoder-1.0.0` não compiladas na placa; (c) VAD sem Silero na imagem; (d) `librosa` não declarado | (a) SIS-2: publicar o P5 como serviço (ou, até lá, o P3 sobe o I5 com `P5_INPUT_MODE=kafka` e o `mock_p5_producer.py` em laço); (b) SIS-1/P3: `examples/whisper_setup.py` do P2 na placa (~1 GB, FP16), com disco e RAM medidos antes; (c) VER-4: carregar o Silero ONNX pelo `onnxruntime`, já instalado, sem torch, ou falhar na partida em vez de cair para energia; (d) VER-4: pôr `librosa` no `requirements-dev.txt` |
| **I6** QR (VER-2) | `inf_a2`, contínuo (vídeo de QR do A2 em laço, `cam0`) | main `89143c9` (sem mudança; a `develop` é mais antiga) | **não testado** como `inf_a2`. A imagem subiu na placa na `inf` (27/11) | `DetectorQR/test_i6.py` (unittest, desde 25/11; o P3 passou a rodar como R-I6) | 18/18 (**notebook** 27/11) | **Não impede subir** em modo teste. (a) Falta confirmar a chave AES que o A2 da nuvem usa; (b) no modo P4, o `leitor.py` da main procura o socket `/tmp/VER2`, mas o P4 cria `/tmp/p4_file_shm` (a `develop` tinha o certo); (c) `ods.i6.image_analysis` recebeu ~625 mil mensagens na nuvem (publica por quadro) | (a) VER-2 informar a chave (o P3 põe no `inf_a2.secrets.env`); (b) VER-2: voltar a `"video": "/tmp/p4_file_shm"` ou ler de variável; (c) VER-2: publicar análise só com código lido, ou com limite de taxa |
| **I7** placas (VER-5) | `inf_a8`, contínuo, detector na GPU (`cam0.mp4` em laço, `cam-entrada`) | **development `9e24056`** (26/11; antes main `1441bbb`). A `development` contém toda a main e acrescenta validação do contrato antes de publicar, `SALVAR_MOSAICOS` e leitura ao vivo | **sim** com o `1441bbb` (Jetson 27/11, nuvem: `inf_a8` 5/0/0); o `9e24056` **não construído** na placa | Sem suíte no repo; aceite `inf_a8` (T-I7C, T-I7, T-I7G, T-I7T, T-C1) | Aceite 5/0/0 com o `1441bbb` (Jetson 27/11). Com o `9e24056`: compila, e um evento do `ConstrutorEventos` dele passa no `validar_i7.py` do P3 (**notebook** 27/11) | Nenhuma que impeça. O `VER5.mp4` da SIS-2 tem placas estrangeiras, e o I7 descarta todas (por isso o P3 usa o `cam0.mp4`); a câmera real do P4 não funciona | VER-5: mesclar a `development` na `main` e fornecer um vídeo com placas brasileiras |
| **I8** peças (VER-1) | `inf_a1`, contínuo (4 eventos de exemplo a cada 60 s) | main `051851f` (sem mudança; `develop` `c182e21`) | **não testado** como `inf_a1`. A imagem subiu na placa na `inf` (27/11) | Suíte de contrato e do publicador (CMD da imagem); T-C1 da `inf_a1` com o validador do A1 | 139 passed (Jetson 24/11); 4/4 eventos no validador do A1 (**notebook** 27/11) | **Não impede subir**, mas **os eventos são SINTÉTICOS**: o repo não tem imagens nem manifesto do modelo (sprint 3). O A1 consome `ods.industria.defeito_classificado` (na 6c: `ods.i8.piece_analysis`) | VER-1: publicar o modelo treinado e um replay com imagens reais (o `replay.py` já faz a inferência pelo P2), e alinhar o tópico com a 6c/B1 |
| **I9** EPI (VER-3) | `inf`, contínuo | `8ae3933` → **`249ac83`** (27/11: Dockerfile da equipe, lotes, B3 externo) | **não testado** com o `249ac83` (o `8ae3933` subiu na placa em 25/11 e 27/11) | `I9/tests` (unittest) | 138/138 (**notebook** 27/11, `249ac83`); 130/130 (Jetson 24/11, `8ae3933`) | **Não impede subir.** Só publica quando o I1 roda VER3 ou VER6, e hoje só o teste do P3 pede essas equipes (veja o I1, item a) | Ver a solução (a) do I1: a VER-3 (A5) mandar o `START` VER3 |

### Dependências de P e de B na placa

| Componente | Quem usa | Situação | Impede subir? |
|---|---|---|---|
| **P2** runtime (SIS-1) | I1 e I7 (biblioteca dentro da imagem, 0.2.0a1 [trt]); I5 (0.2.0a3) | Release 0.2.0a3 já tem Whisper. As imagens do I1 e do I7 seguem na 0.2.0a1, que funciona | Não (o I5 depende das engines do Whisper) |
| **B5** artefatos (MOD-1) | I1 e I7 (pacotes `app-*` da develop do I1; engines compiladas na placa pela `inf_a4`) | Engines prontas em `/var/lib/ods/engines` | Não |
| **P4** vídeo (SIS-2) | Opcional para I1, I6 e I7 (todas leem arquivo nas builds do P3) | `2b136d1` (27/11) toca MP4 em laço. Pendências: `timestamp` nulo no modo arquivo, socket fixo `/tmp/p4_file_shm`, `source_id` fixo `file_<arquivo>` | Não |
| **P5** áudio (SIS-2) | I5 (memória compartilhada ou `ods.p5.audio_chunk`) | Repo só com script de gravação | **Sim, para o I5** |
| **B3** barramento (TRA-1) | Todos (Kafka da nuvem `34.66.235.91:9093`) | Caiu em 23 e 25/11; sem autenticação | Não, enquanto estiver ligado |

## 2. Sob demanda × contínuo: revisão de 27/11/2026

O critério é o que cada A da nuvem consome hoje, no código.

| I | Antes, na `inf` | Agora | Por quê |
|---|---|---|---|
| I1 | pedido por comando | pedido por comando (`inf_a4`) | O A4 comanda o I1 (START/HEARTBEAT/STOP). Contínuo seguraria o único modelo da GPU |
| I2 | contínuo | contínuo (`inf_a4`) | Consome o I1 |
| I3 | sob demanda | sob demanda | É artefato: os consumidores leem a última calibração do tópico |
| I6 | contínuo, QR do P3 (`cam-inf-qr`) | contínuo, QR do A2 (`inf_a2`) | O A2 só reconhece `cam0` e um QR cifrado no formato dele |
| I7 | sob demanda, 20 quadros | **contínuo** (`inf_a8`) | O A8 decide a cancela a cada leitura recente |
| I8 | sob demanda | **contínuo** (`inf_a1`) | O A1 espera eventos chegando |
| I9 | contínuo | contínuo (`inf`) | Consome o I1, mas só há saída quando o I1 roda VER3/VER6 |
| I4, I5 | fora | fora | O A6 e o A7 precisam deles **contínuos**. Quando voltarem, sobem como serviço contínuo, cada um com uma fonte em laço |

## 3. O que falta rodar na placa

1. `git pull` e `./ods.sh trocar inf`: sobe as quatro builds da nuvem e a `inf`, e constrói o I9
   `249ac83` e o I7 `9e24056` (imagem nova `ods-i7-gpu:9e24056…`, ~1,9 GB: confira o disco antes; a
   `ods-i7-gpu:1441bbb…` pode sair depois de o `./inf_a8.sh testar` passar).
2. `./inf.sh testar`, cujo resultado esperado está no guia: `validacao/inf/GUIA-BUILD-INF.md`.
3. `validacao/inf/testar-inf-repos.sh`: agora com o R-I6 e com as imagens das builds da nuvem.
4. Remover as imagens órfãs `ods-i9:8ae3933…` e `ods-i7-gpu:1441bbb…` e os volumes antigos `ods-inf_i7-*`, se o disco apertar.

## 4. Aplicações prontas, em teoria, para rodar na nuvem

"Pronta em teoria" quer dizer que tudo o que a aplicação consome da Jetson, pelo código atual dela,
está de pé e já foi visto no Kafka da nuvem, ou pelo menos tem build pronta para isso. O P3 não roda
as aplicações nem os S's da nuvem, e não sabe se as equipes estão com elas de pé. Conferido no código
das aplicações em 27/11/2026.

| App | Branch mais apta (27/11) | O que consome da Jetson | Quem entrega | Situação | O que falta |
|---|---|---|---|---|---|
| **A8** Estacionamento (VER-5) | `develop` `f50b5a4` (2 commits à frente da main: Kafka da nuvem) | `ods.i7.plate_read` (`cam-entrada`) | `inf_a8` | **Pronta.** I7 validado na placa no Kafka da nuvem (5/0/0, 27/11), com o `1441bbb` | Rodar de novo com o I7 `9e24056`. Pendências do A8 (§8 do CLAUDE.md) não impedem rodar |
| **A4** Esporte (INV-1) | `main` `c280dea` (a `a4-campeonato` ainda tem 1 commit fora) | `ods.i1.command` → `ods.i1.detections` (INV1), `ods.i2.tracks`, `ods.i3.calibration`; o `ods.s1.position` vem do S1 da nuvem | `inf_a4` (I1 + I2) e `inf` (I3) | **Pronta.** `inf_a4` 10/10 no Kafka da nuvem (25/11), e a `cal-INV1-1` já foi publicada | O `INV1.mp4` tem 32 s: o A4 precisa reenviar `START` para a sessão continuar. P7 (pan-tilt) não existe: o A4 fica sem mover a câmera |
| **A2** Acesso (VER-2) | `main` `72cedda` (a `develop` está 2 commits atrás) | `ods.i6.code_read` (`cam0`, QR cifrado no formato do A2) | `inf_a2` | **Pronta, mas não rodada na placa.** O código do QR passou pelo `liberar_entrada` do próprio A2 (notebook). A chave padrão do A2 (`"a"` × 32, `A2_AES_KEY`) é a mesma do P3 | Rodar o `./inf_a2.sh testar` na placa. Confirmar com a VER-2 se a nuvem mudou a `A2_AES_KEY` |
| **A1** Indústria (VER-1) | `main` `5e0f07e` (a build fixa `5d17305`, com o mesmo contrato) | `ods.industria.defeito_classificado` 2.0 | `inf_a1` | **Pronta, com dados SINTÉTICOS e sem rodar na placa.** Os 4 eventos de exemplo do I8 passam no validador do A1 (notebook) | O I8 não tem modelo treinado: o A1 recebe sempre os mesmos 4 eventos. Sem P7 |
| **A5** EPI (VER-3) | `main` `fe2b9a1` | Nada direto da Jetson além do `ods.i3.calibration`: lê `ods.s3.alert` e `ods.s2.*`, que dependem de I1 VER3 → I9 → S2 | `inf` (I9) e `inf_a4` (I1) | **Não pronta.** O I9 sobe, mas só publica quando o I1 roda VER3, e ninguém pede o VER3 (o A5 não manda `START`). As câmeras do A5 não têm calibração publicada | VER-3: mandar `START`/`HEARTBEAT` VER3 ao I1 (como o A4) e enviar as correspondências das câmeras para o I3 |
| **A3** Monitoramento (VER-6) | `dev` (4 commits fora da main; a main tem 1 fora da `dev`) | `ods.s1.zone_occupancy`, `ods.s2.*`, `ods.s3.*`, que dependem de I1 VER6 → I2 → S1 | `inf_a4` (I1 + I2) | **Não pronta.** Ninguém pede o I1 VER6, e o orquestrador roda um modelo por vez (ocupado pelo A4) | VER-6: pedir o VER6 por `ods.i1.command`; MOD-1: atender mais de uma equipe ao mesmo tempo |
| **A6** Libras (APL-2/INV-2) | `main` `5ad584c` | `ods.i4.sign`, `ods.i4.keypoints`, `ods.i4.facial_marker` | nenhuma (I4 fora) | **Não pronta.** I4 fora da build, por decisão do usuário; ao vivo só com webcam | Ver o I4 na tabela geral |
| **A7** Restaurante (VER-4) | `main` `cdaf316` (27/11: consome `ods.i5.transcript`) | `ods.i5.transcript` | nenhuma (I5 fora) | **Não pronta.** I5 fora; P5 sem serviço; engines do Whisper não compiladas | Ver o I5 na tabela geral |

**Resumo:**
- **Prontas, validadas na placa:** A8 e A4.
- **Prontas em teoria (build feita, falta rodar na placa):** A2 e A1 (A1 com eventos sintéticos).
- **Não prontas:** A5 e A3 (falta o pedido do I1 e um I1 que atenda mais de uma equipe), A6 e A7 (I4/I5
  fora e P5 inexistente).
