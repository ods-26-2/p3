# Build "inf": todas as inferências na Jetson

Guia de execução e de teste da build `builds/inf` (P3 · SIS-1). Montada em 24/11/2026.

**Estado:** validada só fora da placa (`docker compose config` com os clones reais, `bash -n`,
`shellcheck` e os scripts contra um `docker` simulado, nos caminhos de sucesso e de falha).
**Nenhuma imagem desta build foi construída na Jetson ainda**, exceto as que ela divide com as
aplicações (`ods-i2`, `ods-i6`, `ods-i9`, se o A8, o A2 e o A5 já as construíram).

## 1. O que sobe

| Inferência | Serviço | Como roda | Entrada | Saída (tópico) |
|---|---|---|---|---|
| I1 detecção | — (build `i1/`) | permanente, GPU | `./inf.sh i1 [EQUIPE] [QUADROS]` → `ods.i1.command` | `ods.i1.detections` |
| I2 rastreio | `i2` | contínuo | `ods.i1.detections` | `ods.i2.tracks` |
| I3 calibração | `i3` | `./inf.sh i3` | imagem da quadra do A4 (repo do I3) | `ods.i3.calibration`, `ods.artifact.published` |
| I4 Libras | `i4-server` + `i4` | contínuo | `./inf.sh i4` (vídeo `teste.mp4` do I4) ou o `webcam.py` do I4 | `ods.i4.sign`, `ods.i4.keypoints`, `ods.i4.facial_marker` |
| I5 fala | `i5` (**fora da build desde 24/11/2026**, comentado no compose; o usuário tem build própria do I5) | — | `./inf.sh i5` (áudio como se fosse o P5, em `ods.p5.audio_chunk`) | `ods.i5.transcript` |
| I6 QR | `i6` | contínuo | `VIDEO_DIR/inf-qr.mp4` em laço (gerado pelo P3) | `ods.i6.code_read` |
| I7 placas | `i7` | `./inf.sh i7`, **detector na GPU** | `VIDEO_DIR/cam0.mp4` (20 quadros amostrados) | `ods.i7.plate_read` |
| I8 peças | `i8` | `./inf.sh i8` | 4 eventos de exemplo do próprio I8 (sem modelo no repo) | `ods.industria.defeito_classificado` |
| I9 EPI | `i9` | contínuo | `ods.i1.detections` (I1 com a equipe VER3/VER6) | `ods.i9.ppe_compliance` |

Commits no `builds/inf/inf.env`. Diferenças em relação às builds das aplicações:

- **I3 `c3d876e`** (o A8/A4 usam `ac28d37`): publicar exige `--registro`; o registro fica no volume `i3-registro`.
- **I4 `503f64b`** (o A6 usa `61b39a1`): agora há o servidor C++ e o reconhecimento ao vivo em container.
- **I5 `d7b1379`** (o A7 usa `cdb00d2`): imagem do P3 em CPU, `ods-i5-cpu`. O `Dockerfile.jetson` da
  equipe usa `l4t-pytorch:r35.2.1` (JetPack 5), que não roda no JetPack 6.2.1 da placa.
- **I7 `1441bbb`** (o A8 usa `a4da4b0`): lê vídeo (`--video`) e o P4 (`--p4`) sozinho. **Detector na GPU**
  (imagem do P3 `ods-i7-gpu`, decisão de 24/11/2026): o pacote `app-plates` 1.0.0 do I7 é o mesmo ONNX do I1
  (sha256 `b698a519…`), então o I7 lê a engine FP16 que o `builds/i1` já compilou em
  `/var/lib/ods/engines/app-plates-1.0.0`. Mesma base `l4t-tensorrt` e mesmo P2 0.2.0a1 do I1, sem PyTorch;
  o OCR fica em CPU. Exige o I1 com as engines prontas (`builds/i1/i1.sh engines`).

## 2. Antes de subir

```bash
cd /opt/ods/p3 && git pull
df -h /                                   # a build constrói ~7 imagens novas: estimativa de 8 a 10 GB
builds/i1/i1.sh status                    # o I1 precisa estar de pé (em builds/i1)
```

- **Disco:** as imagens com PyTorch (I4, I5, I7) são grandes. O `inf.sh` constrói uma por vez, roda
  `docker builder prune -af` depois de cada uma e para abaixo de 4 GB livres. Se não couber, libere
  a build de uma aplicação: `../ods.sh trocar inf` remove as outras e sobe esta.
- **Mesmo Kafka do I1:** o `inf.sh` lê o broker do container do I1 e recusa subir com outro. Com o
  I1 no Kafka da placa (`i1.local.env`): `cp inf.local.env.exemplo inf.local.env`.
- **Memória:** o I4 (MediaPipe + PyTorch), o I5 (Whisper small em float32) e o I7 (quando roda)
  ficam na mesma RAM que o TensorRT do I1. O teste marca `T-I1M` se o I1 reiniciar ou der
  `OUT_OF_MEMORY`. Se der, esvazie o cache de páginas antes (`sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'`).
- **Internet na primeira execução:** o I5 baixa o Whisper (fica no volume `i5-cache`) e o I7, o OCR
  (volume `i7-cache`).

## 3. Subir e testar

```bash
cd /opt/ods/p3/builds/inf
./inf.sh              # ou ../ods.sh trocar inf
./inf.sh status
./inf.sh testar       # → resultados/aceite-inf-<data>.txt
```

O `testar` conta as mensagens de cada tópico, pede 150 quadros do VER3 ao I1, roda I3, I8, I5
(áudio), I4 (vídeo) e I7 em sequência, espera o I9 e conta de novo.

### Resultado esperado

| Item | Esperado | Observação |
|---|---|---|
| T-I1, T-I2, T-I9 | PASSOU | O I1 com `app-epi` no `epi.mp4`; I2 e I9 consomem as detecções |
| T-I1M | PASSOU | Sem reinício nem `OUT_OF_MEMORY` no I1 durante o teste |
| T-I3 | PASSOU | Rodar de novo só reanuncia (`artifact.published`); `calibration` pode não crescer |
| T-I4 | PASSOU ou AVISO | AVISO = pontos-chave publicados, nenhum sinal reconhecido no `teste.mp4` |
| T-I5 | AVISO | I5 fora da build (comentado no compose) |
| T-I6 | PASSOU | Uma leitura por volta do vídeo de QR (20 s) |
| T-I7 | PASSOU ou AVISO | Roda depois do I1 (os dois usam a GPU). FALHOU se a `artifact_version` não terminar em `-fp16` (caiu para CPU). AVISO = nenhuma placa com confiança ≥ 0,9 nos 20 quadros |
| T-I8 | PASSOU | 4 eventos (CONFORMING, NON_CONFORMING, ANOMALY, UNCERTAIN) |

### Para conferir cada um à mão

```bash
./inf.sh contar                 # mensagens por tópico
./inf.sh i1 VER5 50             # placas no cam0.mp4 (I1) → ods.i1.detections e ods.i2.tracks
./inf.sh log i4                 # reconhecimento ao vivo
alias dc='docker compose --env-file inf.env $( [ -f inf.local.env ] && echo --env-file inf.local.env )'
dc logs --tail 30 i5
```

## 4. Suítes de teste das equipes nas imagens da build

O `./inf.sh testar` confere o Kafka. As suítes dos repositórios rodam à parte, dentro das imagens
exatas da build (lidas do `docker compose config`), sem alterar imagem nem código:

```bash
cd /opt/ods/p3/validacao/inf
./testar-inf-repos.sh              # todos (o I1 pelo validacao/i1/testar-i1-servico.sh, na GPU)
./testar-inf-repos.sh --sem-i1     # sem o I1
./testar-inf-repos.sh i2 i9        # só alguns
```

| Item | Suíte | Como roda | Esperado |
|---|---|---|---|
| R-I1 | `I1/tests` + CMD da imagem | `validacao/i1/testar-i1-servico.sh` (build `i1`) | PASSOU (Jetson 24/11: 45 de 46, o `test_05` precisa do `ultralytics`; CMD com `-fp16`) |
| R-I2 | `I2/tests` (unittest) | do clone por volume (o `.dockerignore` do I2 tira os testes da imagem) | PASSOU (o CI da equipe roda a mesma suíte) |
| R-I3 | `I3/tests` (unittest) | testes e `dados/` do clone por volume (idem) | PASSOU (idem) |
| R-I4 | `tests/` (pytest) | do clone por volume; `pytest` instalado no container (precisa de rede) | Jetson 24/11: 74 de 77; os 3 que gravam parquet falham: o pip instala o `pyarrow` 26, que exige numpy 2, e o I4 fixa numpy < 2 (não afeta o ao vivo; recado à INV-2) |
| R-I6, R-I7 | — | o repositório não tem suíte | AVISO |
| R-I8 | contrato e publicador (pytest) | comando padrão da imagem `ods-i8-publisher` | PASSOU (Jetson 24/11: 139 passed) |
| R-I9 | `I9/tests` (unittest) | do clone por volume | PASSOU (Jetson 24/11: 130 OK) |

O que vem do clone tem de estar no commit do `inf.env` (o script confere; outra build pode ter
movido o clone compartilhado). Evidência da 1ª execução: `evidencias/inf-repos-20261124-2228.txt`.

Todas rodam com `--network none` (nada vai para o Kafka), menos a do I4. Relatório em
`validacao/inf/resultados/inf-repos-<data>.txt`; copie para `evidencias/` o que for evidência.

## 5. Riscos conhecidos (primeira construção na placa)

- **I4:** `requirements-i4.txt` pede `mediapipe>=0.10.14` sem teto; a versão mais nova no PyPI (1.2.3)
  tem roda para aarch64, mas não foi testada com o código do I4. O servidor C++ compila o Crow e o
  OpenCV do Ubuntu 24.04 na placa (alguns minutos).
- **I7 (GPU):** imagem do P3 nunca construída na placa. Versões fixadas para o Python 3.10 da base
  (`opencv-python-headless` 4.11.0.86, porque o 4.12+ exige numpy 2 e o P2 pede < 2; `onnxruntime` 1.23.2,
  o último com roda cp310 aarch64). A engine vem do I1: se ele recompilar o `app-plates`, o I7 usa a nova.
  O I7 e o I1 juntos na GPU dividem a RAM: no `testar` o I7 roda depois do I1.
- **I3:** Python 3.14 e `opencv-python-headless` 5.0 (há roda aarch64 no PyPI).
- **I6:** o vídeo de QR é um exemplo do P3, não da VER-2.

## 6. Remover

```bash
./limpar.sh               # containers (volumes ficam)
./limpar.sh --imagens     # também as imagens (as que outra build usa ficam com --manter <app>)
./limpar.sh --tudo        # também volumes (pede "inf") e clones exclusivos
```

O I1 (`builds/i1`) e o vídeo `VIDEO_DIR/inf-qr.mp4` não saem.
