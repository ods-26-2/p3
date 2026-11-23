# Teste individual do I1 na GPU (TensorRT via P2)

> **Build dedicada do I1** (orquestrador sempre de pé, `builds/i1/`): o guia de teste está em [`GUIA-BUILD-I1.md`](GUIA-BUILD-I1.md). Os testes abaixo são do I1 dentro do A8 (`run_detector.py`).

Este teste prova, só com o I1 e sem Kafka, que a detecção roda na GPU da Jetson usando a engine TensorRT compilada pelo P2.

Ele usa apenas o que vem no repositório do I1, no commit `I1_REF` de [`builds/a8/a8.env`](../../builds/a8/a8.env):
- o `Dockerfile.jetson`;
- o pacote B5 `I1/artifacts/app-plates/1.0.0` (ONNX + `metadata.json`);
- as 9 imagens de `fixtures/` desse pacote.

## Como rodar (na Jetson)

```bash
cd /opt/ods/p3/validacao/i1
./testar-i1-gpu.sh               # app-plates + fixtures, com comparação CPU × GPU
./testar-i1-gpu.sh --sem-cpu     # sem a comparação
./testar-i1-gpu.sh --pacote app-epi/1.0.0 --imagens /var/lib/ods/fotos-epi
```

**Na primeira vez,** o teste faz duas coisas demoradas:
- constrói a imagem `ods-i1-gpu:<I1_REF>` (é a mesma do `./a8.sh`; a base `l4t-jetpack` tem vários GB, então confira `df -h /` antes);
- compila a engine em `I1_ENGINES_DIR` (`/var/lib/ods/engines`), o que leva alguns minutos.

**Nas próximas,** reaproveita as duas.

**Kafka:** nada é publicado. O I1 roda em `--mode stdout`, então a cadeia do A8 não recebe detecções de teste.

## O que cada item confirma

| Item | Confirma |
|---|---|
| G01 | É uma Jetson, e o Docker tem o runtime `nvidia` |
| G02 | A imagem importa o TensorRT e o P2, e o P2 escolhe o backend `TrtBackend` |
| G03 | A engine FP16 existe e carrega com o TensorRT da imagem; senão, é compilada (`builds/comum/i1/preparar-engine.sh`, o mesmo script do serviço `i1-engine`) |
| G04 | Inferência direta pelo P2 com `libnvinfer` carregada no processo e `GR3D_FREQ` > 0% no `tegrastats` do host (300 quadros) |
| G05 | O `run_detector.py` do I1 (backend `p2`) processa as imagens e sai com código 0 |
| G06 | Uma mensagem `ods.i1.detections` por imagem, validada pelo próprio I1 contra o schema B1 |
| G07 | `artifact_version` = versão da engine, terminando em `-fp16`; prova que não houve queda para a CPU |
| G08 | Há detecções, todas com classes do pacote |
| G09 | Informativo: latência do mesmo modelo na CPU (ONNX Runtime) comparada à da GPU |

**Resultado:**
- O relatório fica em `resultados/i1-gpu-<data>.txt`, e a pasta de mesmo nome guarda `mensagens.jsonl`, `i1.log`, `engine.log` e `tegrastats.log`.
- A pasta `resultados/` fica fora do Git; copie para `evidencias/` o que for registrar.
- O script termina com código 1 se algum item falhar.

**Validação até agora:** o teste rodou só fora da Jetson, contra um `docker` e um `tegrastats` simulados, nos caminhos de sucesso, de queda para a CPU (`-fp32` e GPU parada) e de placa sem runtime `nvidia`.

# Teste de tempo real do I1 (`testar-i1-tempo-real.sh`)

Responde a duas perguntas: **quanto tempo o I1 leva** para analisar um vídeo, e **se ele acompanha a câmera em tempo real.**

O repositório do I1 só tem testes unitários (`I1/tests/`). Eles rodam com um P2 simulado, e a latência que registram (6,45 ms) é um número fixo do mock, não uma medição.

```bash
cd /opt/ods/p3/validacao/i1
./testar-i1-tempo-real.sh                      # cam0.mp4 do a8.env, alvo = fps do vídeo
./testar-i1-tempo-real.sh --fps-alvo 30        # compara com uma câmera de 30 quadros/s
./testar-i1-tempo-real.sh --video /var/lib/ods/videos/outro.mp4 --sem-cadeia
```

**Pré-requisito:** a imagem `ods-i1-gpu:<I1_REF>` e a engine já existem (`./testar-i1-gpu.sh` ou `./a8.sh`). Este teste não constrói nada nem publica no Kafka.

**Parte 1 — capacidade:**
- O I1 lê o MP4 direto do arquivo, o mais rápido que consegue.
- Mede o tempo total (subir o container e carregar a engine, mais o processamento).
- Calcula a vazão, em quadros/s, e o tempo por quadro, da leitura à publicação (mediana, p95 e máximo).
- Registra a inferência média, informada pelo I1, e o `GR3D_FREQ` máximo.
- Se a vazão é maior que o fps da câmera, o I1 acompanha em tempo real. A folga diz quantas vezes sobra.

**Parte 2 — no ritmo real:** usa a última execução do `./a8.sh testar`. Lê as mensagens que o I1 da cadeia gravou e mede:
- o atraso entre o P4 capturar o quadro e o I1 publicar;
- quantos quadros o I1 não chegou a ver, no começo (antes de conectar) e no meio.

| Item | Confirma |
|---|---|
| R01 | Imagem, engine, vídeo e runtime `nvidia` presentes |
| R02 | Todos os quadros do vídeo processados (tolerância de 1% na contagem do OpenCV), código 0 |
| R03 | `artifact_version` termina em `-fp16`: rodou no TensorRT |
| R04 | Vazão ≥ fps alvo: acompanha em tempo real (FALHOU se não acompanha) |
| R05 | p95 do tempo por quadro < intervalo entre quadros (AVISO se não) |
| R06 | Cadeia do A8: nenhum quadro perdido no meio e até 5 no começo (AVISO se não) |

**Limite da medida:** na parte 1, o `captured_at` é marcado depois de o OpenCV decodificar o quadro na CPU. O "tempo por quadro" não inclui a decodificação; a vazão inclui.

**Validação:** rodado na Jetson em 14/11/2026 (evidência em [`evidencias/i1-tempo-real-2026-11-14.txt`](evidencias/i1-tempo-real-2026-11-14.txt)): 25 quadros/s com os relógios dinâmicos do modo 25W e 64 quadros/s com `jetson_clocks`. Naquela rodada o R05 saiu errado por causa do locale pt_BR (vírgula decimal); o script já força o ponto.

# Testes do próprio I1 no serviço da build (`testar-i1-servico.sh`)

Roda a suíte de testes do repositório do I1 (`I1/tests`, 40 testes `unittest`) e o comando padrão da imagem **dentro do mesmo serviço que o `./a8.sh` sobe.**

A definição vem do `docker compose config` do `builds/a8`:
- mesma imagem `ods-i1-gpu:<I1_REF>`, da `develop`;
- runtime `nvidia`;
- mesmas variáveis (`P2_BACKEND=trt`, `P2_ENGINE_DIR`, `ODS_KAFKA_BROKER`);
- mesma pasta de engines.

Só ficam de fora o `ipc: service:p4` e a memória compartilhada em `/tmp`, que exigem o P4 tocando vídeo. Nada é publicado no Kafka.

```bash
cd /opt/ods/p3/validacao/i1
./testar-i1-servico.sh
```

| Item | Confirma |
|---|---|
| S01 | A imagem do serviço existe e é a do commit fixado (`I1_REF`) |
| S02 | A suíte do I1 passa dentro do serviço. O `test_05` (Degrau A pelo caminho de CPU) precisa do `ultralytics`, que a imagem Jetson não instala; esse erro é esperado e aceito, qualquer outro falha o item |
| S03 | O comando padrão da imagem (`CMD` do `Dockerfile.jetson`: `run_detector` nas fixtures, backend `p2`) termina com código 0, publica mensagens validadas pelo I1 e tem `artifact_version` terminando em `-fp16` (GPU) |

**Limite:** os testes do I1 simulam o P2. Só o S03, e os outros testes desta pasta, exercitam o TensorRT de verdade.

**Validação:** rodado na Jetson em 14/11/2026: S01, S02 (39 de 40, só o `test_05`) e S03 (9 mensagens `-fp16`) passaram. Evidência em [`evidencias/i1-servico-2026-11-14.txt`](evidencias/i1-servico-2026-11-14.txt).
