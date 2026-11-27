# Journal — P3 (SIS-1) · builds ODS 2026/2

Estado do P3, pedidos, pendências, tarefas recentes, mensagens às equipes e resultados. **Atualizado a
cada pedido** (o mais novo em cima em cada seção).

- **Este arquivo:** o retrato do projeto, para quem chega agora.
- **`CLAUDE.md`:** regras e contexto técnico (Jetson, Kafka, lições, pendências por equipe na §8).
- **`temp/PROGRESSO.md`:** o diário detalhado, passo a passo (o antigo está em `temp/PROGRESSO-arquivo-*.md`).

Última atualização: **27/11/2026**.

---

## 1. Estado atual

### Arranjo (desde 23/11/2026)

- As aplicações rodam na nuvem; a Jetson roda as inferências (os I's).
- Kafka da nuvem: `34.66.235.91:9093`. O container `kafka` da placa (de outro grupo) tem de continuar
  de pé, mesmo sem as builds o usarem.
- O A4, o S1 e o I3 de registro do A4 rodam na nuvem; a placa entrega ao A4 o I1, o I2 e o I3 pela
  build `inf_a4`.
- Placa: `jetson_clocks` aplicado em 26/11 (CPU 1,728 GHz, GPU 1020 MHz, ventoinha no máximo; modo 25W;
  **não persiste** depois de reiniciar). Disco: ~4 GB livres (no limite).

### Builds

| Build | O que sobe | Kafka | Estado | Última validação na placa |
|---|---|---|---|---|
| `inf_a4` (era `inf_restrita`) | I1 próprio (GPU) + I2; I3 sob demanda | nuvem | De pé | 25/11: `testar` PASSOU 10/0/0 (nuvem). 27/11: `./inf_a4.sh p4` (P4 da SIS-2 → I1): 150 detecções e 150 trilhas, relatório `.txt` não conferido |
| `i1` (permanente) | orquestrador do I1 | nuvem | **Fica parado** (decisão de 27/11: a `inf` usa o I1 da `inf_a4`) | 24/11: `testar` PASSOU 16, AVISO 1 |
| `inf_a1` | I8 **contínuo** (4 eventos de exemplo do I8, SINTÉTICOS, a cada 60 s) para o A1 da nuvem; I1 VER1 sob demanda pela `inf_a4` | nuvem | **Nova em 27/11, não rodada na placa** | — (só no notebook) |
| `inf_a2` | I6 **contínuo** (vídeo de QR do P3, aceito pelas regras do A2, `cam0`) para o A2 da nuvem | nuvem | **Nova em 27/11, não rodada na placa** | — (só no notebook) |
| `inf_a8` | I7 **contínuo** (VER5.mp4 em laço, no ritmo do vídeo, `cam-entrada`) para o A8 da nuvem; I1 VER5 sob demanda pela `inf_a4` | nuvem | **De pé na placa**; falta comprimir e copiar para o notebook (`./guardar-no-notebook.sh`) | **27/11 (nuvem, `cam0.mp4`): `testar` PASSOU 5/0/0** |
| `inf` | I3, I6, I7, I8, I9 **sobre a `inf_a4`** (usa o I1 e o I2 dela desde 27/11); **I4 e I5 fora** | nuvem | De pé (sobre a `inf_a4`) | **27/11 (nuvem): `testar` PASSOU 8, FALHOU 0, AVISO 2** (I4, I5 fora) |
| `a8` | A8 + cadeia P4 → I1 → I2 → S1 → S4/S5 + I7 | placa | Referência | 14/11: PASSOU 11, FALHOU 2 (esperados). Imagens guardadas no PC em 25/11 |
| `a5` | A5 + P4 → I1 (EPI) → I9/I2 → S1, S3, S4 | placa | Validada com falhas conhecidas | 18/11: PASSOU 9, FALHOU 2, BLOQUEADO 1, AVISO 1 |
| `a2` | A2 + I6 + S4 | placa | Preparada em 17/11, **alterações sem commit**, nunca rodada | — |
| `a1`, `a3`, `a6`, `a7` | (13/11) | placa | Escritas, nunca rodadas | — |
| `a4` | (13/11) | placa | **Superada**: o A4 roda na nuvem e usa a `inf_a4` | — |

---

## 2. Pedidos do usuário (mais recentes primeiro)

| Data | Pedido | Resultado |
|---|---|---|
| 27/11 | Fazer a `inf_a2` e a build da próxima melhor aplicação (o usuário está guardando a `inf_a8` no notebook) | `inf_a2`: I6 contínuo com um QR gerado pelo P3 no formato do A2 (validado com o código da VER-2), validada no notebook. Próxima aplicação: **A1** (`inf_a1`: o publicador oficial do I8 com os 4 eventos de exemplo dele, SINTÉTICOS porque o I8 não tem imagens, em laço; os eventos passaram 4/4 no validador do A1). O A3 e o A5 só consomem serviços, e o A6 e o A7 dependem do I4 e do I5, que estão fora. As duas builds foram validadas só no notebook |
| 27/11 | Trouxe o `./inf_a8.sh testar` com o `cam0.mp4` | **PASSOU 5, FALHOU 0, AVISO 0**: 9 placas válidas no Kafka da nuvem, na GPU, captura→publicação em 0,1 s, sem reinício. Falta guardar a `inf_a8` no notebook |
| 27/11 | A pasta da SIS-2 só tem INV1, INV2, VER2, VER2_2 e VER5; a câmera real do P4 não funciona | O `cam0.mp4` está na pasta do P3 (`/var/lib/ods/videos`) e passou a ser o padrão da `inf_a8` (`I7_VIDEO_DIR`/`I7_VIDEO`), com o VER5.mp4 só para o I1. Sem commit |
| 27/11 | Trouxe o log do I7 da `inf_a8` | Ritmo e GPU OK: VER5.mp4 tem 300 s a 60 q/s e o I7 lê 2 q/s com `-fp16`. As placas do VER5.mp4 não são brasileiras (ex.: `34A36837`): todas saem "Inválida" e nada é publicado. Proposto trocar para o `cam0.mp4` da VER-5 (aguarda o usuário); espera do teste subiu para 420 s |
| 27/11 | Trouxe o 1º `./inf_a8.sh testar` da placa | PASSOU 1, FALHOU 3, AVISO 2: o I7 ficou de pé sem reinício, mas não publicou nenhuma placa em 300 s (ainda na 1ª volta). Causa a apurar pelo log. O T-I7G passou a ler a versão do log quando não há mensagens, e o relatório mostra o progresso do I7 quando não há leitura (sem commit) |
| 27/11 | `inf_a8` está rodando na placa; ver que outra aplicação pode receber uma build de inferência | Anotado: falta guardar a `inf_a8` no notebook. Indicado o **A2** (`inf_a2`: I6 contínuo em CPU, `source_id` `cam0`); falta um QR que o A2 aceite (AES, CPF de teste, janela de validade). Depois vem o A1 (I8 por replay, com modelos no repo, mais o I1 VER1; P7 ausente). O A3 e o A5 só consomem serviços (S1–S4), e o A6 e o A7 dependem do I4 e do I5, que estão fora |
| 27/11 | Criar a `inf_a8`: I7 contínuo com o VER5.mp4 e Kafka da nuvem; ver como as outras inferências atendem melhor o A8; script para guardar no notebook; os scripts deixam arquivos comprimidos na placa? | `builds/inf_a8` (I7 contínuo em laço, no ritmo do vídeo, `cam-entrada`; I1 VER5 sob demanda pela `inf_a4`; I2/I3/I6 fora); `guardar-no-notebook.sh` e `subir-do-notebook.sh`; `ods.sh`: `inf_a4` e `inf_a8` convivem. Validado só em simulação. Nenhum script grava arquivo comprimido na placa: tudo passa pelo ssh |
| 27/11 | O que deixaria o I7 contínuo? O P3 pode fazer? | Sim, só com compose, sem mexer no código do I7 `1441bbb`. Ele já tem `--p4 video\|imx519\|imx477`, que roda até ficar `P4_ESPERA_S` sem quadros e reconecta sozinho, e `--video`, que termina no fim do arquivo. Contínuo = `--p4` sem `-n`, com `P4_ESPERA_S` alto e `restart: unless-stopped`, `ipc: host` e o `/tmp` da placa; ou vídeo em laço pelo restart. Fica fora do P3: o P4 da SIS-2 ligado o tempo todo e a câmera |
| 27/11 | Qual aplicação está mais perto de uma build completa? O A8 antigo ainda funciona? | Indicado o **A4**: a INV-1 integrou com o I1 da Jetson (24–26/11), tem Dockerfiles, roda na nuvem e a `inf_a4` já passou 10/10; falta o ponta a ponta real, o S4 e o P4 como câmera; o P7 está bloqueado. **A8 na placa:** deve funcionar como em 14/11 (mesmos caminhos do I1, o código do A8 só mudou o broker), mas reconstrói ~8 imagens (~2 h), pesa no disco e o `trocar a8` derruba a `inf_a4`, deixando o A4 da nuvem sem I1. A homologação do A8 hoje é na nuvem e só precisa do I7 da placa publicando lá |
| 27/11 | Garantir I4 e I5 fora da `inf`; script para guardar a `inf` no notebook, como o da `inf_a4` | `I4_REF`/`I5_REF` e variáveis comentados no `inf.env` (não clona mais); guia sem I4 ativo; `builds/inf/guardar-no-notebook.sh` (imagens I3, I6, I7, I8, I9; `--com-engine`, `--comprimir-na-placa`), validado só em simulação |
| 27/11 | Trouxe o `testar` da `inf` no arranjo novo (e antes o `git pull` barrado por edições à mão) | PASSOU 8, FALHOU 0, AVISO 2; evidência versionada. Edições à mão na placa (I5 `4d79472` religado) guardadas em `git stash` |
| 27/11 | Confirmar se a `inf` sobe tudo o que os I's precisam (sem I4/I5) | Sim: I1/I2 e engines pela `inf_a4`; I3, I6, I7, I8, I9 pela `inf`; P4 não entra (vídeo de arquivo) |
| 27/11 | Pergunta: com a placa vazia, o que sobe? O que dispara o I3, o I7 e o I8? | Respondido: só o `./ods.sh trocar inf` sobe a `inf_a4` junto (o `./inf.sh` sozinho, não); I3, I7 e I8 só rodam por comando (`./inf.sh i3/i7/i8` ou `./inf.sh testar`) |
| 27/11 | I4 e I5 fora da build por enquanto | I4 comentado no compose (como o I5), fora do teste (T-I4 = AVISO) e das suítes; commit de 27/11 ("inf: roda sobre a inf_a4…") |
| 27/11 | Decisões para levantar todas as infs: I5 fora com recado; a `inf` usa o I1 da `inf_a4`; I2, I3 e I6 atualizados | Feito e commitado: `inf` sem I1/I2 próprios, pedido ao I1 com `"source"` do P3, `ods.sh trocar inf` mantém e sobe a `inf_a4`, `--manter` com várias builds; recado à VER-4 escrito (§4.2). **Falta rodar na placa** (§3, item 1) |
| 27/11 | Levantar todas as infs; checar se o I4 e o I5 fizeram as alterações pendentes; criar este journal | Levantamento feito (§5). Journal criado |
| 27/11 | Recado à MOD-1 (I1 e o `timestamp` nulo do P4) | **Deixado para depois** (registrado em §3) |
| 27/11 | Recado à SIS-2 sobre o `timestamp` nulo do P4 | Escrito (texto no §4.1). Envio: com o usuário |
| 26/11 | Regra: o P3 não altera nada do P4 nem das pastas do `sys2` | Aplicada ao `./inf_a4.sh p4` e registrada no CLAUDE.md §4 (`a3edb8d`) |
| 26/11 | `./inf_a4.sh p4` para conferir o P4 e a ligação com o I1 | Feito (`a3edb8d`); 1ª execução na placa em 27/11 |
| 26/11 | Comprimir na placa para guardar/subir de casa | `--comprimir-na-placa` / `--descomprimir-na-placa` (`de28d12`) |
| 26/11 | Renomear `inf_restrita` → `inf_a4`, scripts de guardar/subir pelo notebook, I3 `0a7f944` | Feito (`61597b1`) |
| 26/11 | Modo mais performático da placa | `jetson_clocks` aplicado pelo usuário (MAXN SUPER não aplicado) |
| 26/11 | O que falta para os I's do A4; o P6 deveria estar na placa? | Análise: nada a acrescentar na `inf_a4` no arranjo atual (P4 só para câmera ao vivo); o P6 não entrega quadros |
| 25/11 | Build só com I1, I2 e I3, Kafka da nuvem, vídeos da pasta original da SIS-2 | `inf_restrita` (`7ea744f`, `434a542`, `e1476e2`) |
| 24/11 | Build única com todas as inferências; I7 na GPU; I5 fora | `inf` (`73564ba`, `b9fa5a7`, `e105e37`, `b879079`, `9153d5c`, `771a237`) |
| 23/11 | Build dedicada do I1 (sempre de pé) | `i1` (`ff7f7e4`, `576536f`, `80d2b67`, `9eb1ea4`) |
| 17–18/11 | Preparar o A2; trocar o foco para o A5 | A2 sem commit; A5 validado na placa |
| 13–14/11 | Builds A1–A8, estrutura comum, I1 na GPU no A8 | A8 validado na placa; demais escritas |

---

## 3. Pendências do P3 (próximos passos)

0. **`inf_a8` de pé na placa (27/11):** comprimir e copiar para o notebook (`builds/inf_a8/guardar-no-notebook.sh`, no notebook); trazer o `./inf_a8.sh testar`.
1. **Infs na placa: feito em 27/11** (PASSOU 8/0/2). Sobras:
   - imagens órfãs `ods-i4:503f64b…`, `ods-i4-server:503f64b…` e `ods-i4-video:p3-1` (remover à mão só se o
     usuário quiser); os clones `i4`/`i5` já feitos em `SRC_DIR` ficam (o `inf.env` não os lista mais);
   - na placa: `git stash` com o I5 `4d79472` religado à mão (não portado: contraria a decisão e o I5
     devolve transcrição falsa), `builds/i5/` staged sem commit, backups `*.bak-*`, `inf.local.env.placa`
     (a lib não lê) e `builds/inf/.docker-compose.yml.swp`;
   - `ods.i6.image_analysis` com ~625 mil mensagens na nuvem (+383 em ~1,5 min): o I6 contínuo publica
     por quadro do vídeo em laço; parar o `i6` quando não estiver em teste, ou avaliar com a VER-2.
2. **Fechar o teste do P4:** trazer `resultados/p4-i1-*.txt` e a faixa de `frame_index`; rodar
   `./inf_a4.sh p4 --desfazer`; copiar a evidência para `validacao/inf_a4/evidencias/`.
3. **Evidências da `inf_a4`:** copiar `aceite-inf_restrita-20261125-161228.txt` e `-162407.txt` da placa
   para `validacao/inf_a4/evidencias/`.
4. **Recado à MOD-1** (a fazer): o I1 ler o `received_at_*` quando o `timestamp` do P4 vier nulo, e
   combinar o relógio (o I1 converte como `CLOCK_MONOTONIC`, e o P4 usa `CLOCK_MONOTONIC_RAW`).
5. **Recado à VER-4 (I5):** escrito em 27/11 (§4.2); falta enviar.
6. **Teste de ponta a ponta com o A4 real:** criar uma partida no A4 e contar `ods.i1.detections` →
   `ods.i2.tracks` → `ods.s1.position` na nuvem.
7. **Guardar a `inf_a4` no notebook:** de casa, só se `ssh ods@200.17.66.56` responder.
8. **A2:** alterações de 17/11 sem commit (`builds/a2`, `validacao/a2`).
9. **Placa:** decidir com a SIS-1 sobre MAXN SUPER e `jetson_clocks` permanente.
10. Volume órfão `ods-inf_restrita_i3-registro` na placa (pequeno; remover só se o usuário pedir).
11. Tag `a8-cadeia-v1`: proposta, a conferir com o usuário.
12. Opcional, cadeia da 6c: validar pelo contrato central (B4/B1) e compor o P4 na `inf_a4`.

---

## 4. Mensagens às equipes

| Data | Para | Assunto | Estado |
|---|---|---|---|
| 27/11 | SIS-2 (P4) | `timestamp` nulo no modo arquivo | Escrita (§4.1); envio com o usuário |
| — | MOD-1 (I1) | I1 com `timestamp` nulo do P4; relógio MONOTONIC × MONOTONIC_RAW | A fazer (decisão de 27/11) |
| 27/11 | VER-4 (I5) | Imagem da Jetson devolve transcrição fixa | Escrita (§4.2); envio com o usuário |
| 26/11 | TRA-2 (P6) | O que falta no P6 (quadros, gravação real, SEEK/RESTART, broker) | Lista pronta; recado não escrito |
| 24/11 | INV-2 (I4) | Teto para o `pyarrow` (ex.: `17.0.0`), `mediapipe` sem versão | Sugerido; **sem mudança no repo até 27/11** |

### 4.1 SIS-2: `timestamp` nulo no modo arquivo (27/11)

> **Assunto: P4 no modo arquivo envia `timestamp` nulo, e o I1 passa a usar a hora da leitura como `captured_at`**
>
> Testamos o P4 (`/home/sys2/SIS-2/p4`, modo `video` com `INV1.mp4`) alimentando o I1 pela memória
> compartilhada, na Jetson, em 27/11 às 01:18 UTC. A ligação funcionou: o I1 leu 150 quadros e adotou o
> `source_id` (`file_INV1`) e a sessão do P4.
>
> - No modo arquivo, o P4 envia `"timestamp": null` em todos os quadros, no cabeçalho da memória
>   compartilhada e no `ods.p4.frame`. A causa está em `src/p4.py`, no ramo
>   `timestamp_origin == "file_playback_raw"` (`captured_at_ns = None`). As câmeras preenchem o campo.
> - O I1 lê só o `timestamp`; quando ele vem nulo, usa a hora da leitura como `captured_at`. O tempo que
>   desce pela cadeia (I1 → I2 → S1 → A4) deixa de ser o do quadro, e o A4 já precisou de contorno
>   próprio (`A4_RELOGIO_QUADRO`).
> - Sugestão: no modo arquivo, preencher `timestamp` com o instante de entrega (o código já tem
>   `frame.timestamp_ns` e `received_at_ns`), opcionalmente com `"timestamp_origin": "file_playback"`, e
>   documentar o relógio do campo. Se preferirem manter `null`, avisem, para combinarmos com a MOD-1.
> - O P3 não alterou nada no P4 nem na pasta de vocês.

### 4.2 VER-4: I5 na Jetson devolve transcrição fixa (27/11)

> **Assunto: I5 `4d79472` na Jetson publica transcrição fixa, sem Whisper e sem GPU**
>
> Conferimos o I5 da `main` (`4d79472`, 25/11). A troca do `Dockerfile.jetson` para
> `nvcr.io/nvidia/l4t-tensorrt:r10.3.0-runtime` resolve a base de JetPack 5, e é a mesma base que o I1
> já usa na placa. Mas, com o PyTorch e o Transformers fora do `requirements.txt`, a transcrição deixa
> de existir na imagem:
>
> - O `src/p2_runtime.py` é uma implementação local da interface do P2, não a biblioteca do SIS-1. Sem
>   PyTorch, `_create_local_whisper_backend` devolve `None`, e o `infer` cai em
>   `_default_engine_execution`.
> - Essa função devolve sempre o texto **"Transcrição processada via engine acelerado P2"**, com uma
>   confiança calculada pela energia do áudio (0,55 a 0,96). Ou seja, a imagem publicaria em
>   `ods.i5.transcript` um texto fixo com aparência de resultado real, e não usa GPU nem TensorRT.
> - O pacote real do P2 não é instalado. A versão 0.2.0a3 já traz Whisper (veja `ods-26-2/p2`,
>   `docs/guia-rapido.md`).
>
> Sugestões:
> 1. Usar o P2 do SIS-1 (instalar o wheel na imagem) para o Whisper na GPU, com a engine publicada
>    pelo B5/P2. Ou, enquanto ele não estiver pronto, manter o Whisper local em CPU na imagem.
> 2. Quando nenhum backend real carregar, **falhar** (erro na partida ou `ERROR` no evento), em vez de
>    publicar o texto fixo.
> 3. Fixar as versões do `requirements.txt` (hoje todas `>=`) e permitir trocar o broker por variável de
>    ambiente (hoje `34.66.235.91:9093` fica fixo no YAML e no código).
>
> Enquanto isso, o P3 mantém o I5 fora da build de inferências da placa. O P3 não alterou nada no
> repositório de vocês.

---

## 5. Levantamento de 27/11: as inferências frente aos repositórios

Commits fixados na `inf` × ponta atual de cada repositório:

| I | Fixado | Repo | O que mudou | Pendência antiga |
|---|---|---|---|---|
| I2 | `5283d60` | `5f4957c` (25/11) | Só o `HOW_TO_RUN.md` (roteiro da Jetson, Kafka da nuvem) | — |
| I3 | `c3d876e` (`inf`) / `0a7f944` (`inf_a4`) | `0a7f944` | Só documentação | — |
| **I4** | `503f64b` | `503f64b` | **Nada desde 17/11** | **Nenhuma resolvida:** `pyarrow>=15` sem teto (com `numpy<2`, 3 testes falham), `mediapipe>=0.10.14` sem versão fixa, `webcam.py` só abre câmera por índice, repo `s6` vazio |
| **I5** | `d7b1379` | `4d79472` (25/11) | `Dockerfile.jetson` passou para `l4t-tensorrt:r10.3.0-runtime` (JetPack 6, a mesma base do I1, já na placa); PyTorch e Transformers saíram do `requirements.txt` | Base JetPack 5: **resolvida**. **Novo defeito:** veja abaixo |
| I6 | `86ae5d7` | `89143c9` (25/11) | Lê o P4 pela memória compartilhada (`I6_SOURCE_MODE=video\|camera\|ambos`), além do TCP; `I6_TEST_MODE=false` no exemplo | "Espera socket TCP que o P4 não oferece": **resolvida em parte** (falta testar) |
| I7 | `1441bbb` | igual | — | Não lê o P4 |
| I8 | `051851f` | igual | — | Sem modelo treinado (mocks) |
| I9 | `8ae3933` | igual | — | Sem Dockerfile |

**I5, defeito novo (`4d79472`):**
- O `src/p2_runtime.py` do I5 **não é o P2 do SIS-1**: é uma imitação local da interface.
- Sem PyTorch na imagem, o "Whisper local" não carrega, e o `infer` cai em `_default_engine_execution`.
  Essa função devolve sempre o texto **"Transcrição processada via engine acelerado P2"**, com uma
  confiança calculada pelo volume do áudio.
- Ou seja: a imagem nova da Jetson publica transcrições falsas e não usa a GPU nem o TensorRT. O
  `d7b1379` ainda transcrevia de verdade, na CPU.
- Também: o broker padrão da nuvem continua fixo no YAML e no código, as dependências não têm versão
  fixa (`>=`), e o pacote real do P2 (0.2.0a3 já traz Whisper) não é instalado.

---

## 6. Resultados e evidências

| Data | Build | Resultado | Onde |
|---|---|---|---|
| 27/11 | `inf_a8` (nuvem, `cam0.mp4`) | PASSOU 5, FALHOU 0, AVISO 0: 9 placas válidas, `-fp16`, 0,1 s, RAM 3,8 GB livres | `validacao/inf_a8/evidencias/aceite-inf_a8-20261127-020650.txt` |
| 27/11 | `inf_a8` (nuvem) | PASSOU 1, FALHOU 3, AVISO 1: I7 de pé, sem placa publicada em 300 s | `validacao/inf_a8/evidencias/aceite-inf_a8-20261127-014819.txt` |
| 27/11 | `inf` sobre a `inf_a4` (nuvem) | PASSOU 8, FALHOU 0, AVISO 2 (I4, I5 fora); I7 `-fp16`; I1 sem reinício; RAM 3,9 GB livres | `validacao/inf/evidencias/aceite-inf-20261127-005013.txt` |
| 27/11 | `inf_a4` + P4 | P4 → I1: 150 detecções e 150 trilhas; sessão e `source_id` do P4 propagados; I1 perdeu ~616 quadros na partida (~13,5 s de carga) e processou ~18 quadros/s com o P4 a 30 | Logs trazidos pelo usuário (relatório `.txt` pendente) |
| 25/11 | `inf_restrita` (nuvem) | PASSOU 10, FALHOU 0 | Na placa: `resultados/aceite-inf_restrita-20261125-162407.txt` |
| 25/11 | `inf_restrita` (placa) | PASSOU 10, FALHOU 0 | Na placa: `resultados/aceite-inf_restrita-20261125-161228.txt` |
| 25/11 | `inf` | PASSOU 9, FALHOU 0, AVISO 1 | `validacao/inf/evidencias/aceite-inf-20261125-080428.txt` |
| 24/11 | suítes das equipes (`inf`) | I1 45/46, I2 35, I3 33, I8 139, I9 130; I4 74/77 | `validacao/inf/evidencias/inf-repos-20261124-2228.txt` |
| 24/11 | `i1` | PASSOU 16, FALHOU 0, AVISO 1 | `validacao/i1/evidencias/aceite-i1-20261124-011649.txt` |
| 18/11 | `a5` | PASSOU 9, FALHOU 2, BLOQUEADO 1, AVISO 1 | `validacao/a5/evidencias/aceite-a5-20261118-131217.txt` |
| 14/11 | `a8` | PASSOU 11, FALHOU 2 (C14, C18), BLOQUEADO 3, AVISO 2 | `validacao/a8/evidencias/aceite-a8-20261114-175800.txt` |
| 14/11 | I1 (GPU) | 25 quadros/s (64 com `jetson_clocks`); suíte 39/40 no serviço | `validacao/i1/evidencias/` |

**Tag:** `a8-minimo-v1`.

---

## 7. Pendências com as equipes (resumo; a tabela completa está no CLAUDE.md §8)

- **SIS-2 (P4):** `timestamp` nulo no modo arquivo; socket e `source_id` fixos no código; envelope fora
  da 6c; P5 e P7 sem serviço.
- **MOD-1 (I1):** fim do vídeo com código 1; sem sinal de "pronto" ao P4; `ods.i1.command` sem contrato;
  erros que derrubam a fila; tratar o `timestamp` nulo do P4.
- **VER-4 (I5):** transcrição falsa na imagem da Jetson (`4d79472`); recado escrito em 27/11.
- **INV-2 (I4):** `pyarrow` e `mediapipe` sem versão fixa (sem mudança até 27/11).
- **TRA-2 (P6):** não entrega quadros nem grava de verdade.
- **TRA-1 (B3):** Kafka da turma sem `restart` e sem autenticação; o da nuvem já caiu (23 e 25/11).
- **VER-6 (S2):** S2 fora do Kafka (bloqueia A3 e A5 nos eventos).

---

## 8. Histórico deste arquivo

- **27/11/2026:** build `inf_a8` (I7 contínuo para o A8).
- **27/11/2026:** I4/I5 fora também do `inf.env`; `inf/guardar-no-notebook.sh`.
- **27/11/2026:** `inf` validada na placa no arranjo novo (PASSOU 8/0/2).
- **27/11/2026:** I4 fora da build `inf`; tudo de 27/11 commitado ("inf: roda sobre a inf_a4…").
- **27/11/2026:** decisões para levantar as infs aplicadas; recado à VER-4.
- **27/11/2026:** criado (pedido do usuário), com o estado até o levantamento das inferências.
