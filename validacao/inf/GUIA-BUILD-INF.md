# Build "inf": todas as inferências na Jetson

Guia de execução e de teste da build `builds/inf` (P3 · SIS-1). Montada em 24/11/2026.

> **Desde 27/11/2026 (à tarde) a `inf` roda sobre as builds das aplicações da nuvem** (decisão do
> usuário). O I6, o I7 e o I8 que a `inf` tinha não atendiam aos A's da nuvem: o I6 lia um QR do P3
> com `source_id` `cam-inf-qr`, que o A2 não reconhece, e o I7 e o I8 só rodavam por comando, mas o A8
> e o A1 precisam deles contínuos. As versões certas já estavam nas builds por aplicação:
>
> | Build | O que entrega | A da nuvem |
> |---|---|---|
> | `inf_a4` | I1 (orquestrador na GPU) + I2 contínuo | A4 (e o I9 daqui) |
> | `inf_a1` | I8 contínuo (eventos de exemplo a cada 60 s) | A1 |
> | `inf_a2` | I6 contínuo (QR no formato do A2, `cam0`) | A2 |
> | `inf_a8` | I7 contínuo na GPU (`cam0.mp4` em laço, `cam-entrada`) | A8 |
>
> `../ods.sh trocar inf` mantém e sobe as quatro antes. A `inf` fica só com o que nenhuma delas tem:
> **o I9 contínuo e o I3 da quadra de teste (sob demanda)**. Um I6, I7 ou I8 próprio duplicaria as
> publicações nos tópicos que os A's leem, e o I7 dividiria a GPU com o da `inf_a8`. O I1 permanente
> (`builds/i1`) fica parado. **I4 e I5 continuam fora** (decisão do usuário, 27/11): os commits novos
> (I4 `d6a2185`, I5 `aabe73b`) foram conferidos e ficam comentados no `inf.env`. Veja
> [`situacao_componentes.md`](../../situacao_componentes.md) para o estado de cada componente.

**Estado (27/11/2026, tarde):** arranjo novo validado **só no notebook** (`bash -n`, YAML e o
`./inf.sh testar`/`status`/`ods.sh trocar inf` contra um `docker` simulado: tudo de pé, 8/0/2; sem a
`inf_a8`, T-I7 FALHOU sem gastar a espera; I7 em `-fp32`, T-I7 FALHOU). Sem `docker compose` no
notebook. I9 passou para `249ac83`, com o Dockerfile da equipe (suíte 138/138 no notebook). **Falta
rodar na placa.**

**Antes (27/11/2026, manhã, Kafka da nuvem, com I6/I7/I8 próprios):** PASSOU 8, FALHOU 0, AVISO 2
(T-I4 e T-I5, fora) — `evidencias/aceite-inf-20261127-005013.txt`. **25/11 (Kafka da placa):** PASSOU 9,
FALHOU 0, AVISO 1 — `evidencias/aceite-inf-20261125-080428.txt`.

## 1. O que sobe

| Inferência | Onde | Como roda | Entrada | Saída (tópico) |
|---|---|---|---|---|
| I1 detecção | build `inf_a4/` | contínuo, GPU, um modelo por vez | `./inf.sh i1 [EQUIPE] [QUADROS]` → `ods.i1.command` | `ods.i1.detections` |
| I2 rastreio | build `inf_a4/` | contínuo | `ods.i1.detections` | `ods.i2.tracks` |
| I3 calibração | `i3` (aqui) | sob demanda: `./inf.sh i3` | imagem da quadra (repo do I3), `source_id` `inf-quadra` | `ods.i3.calibration`, `ods.artifact.published` |
| I4 Libras | **fora** (comentado no compose) | — | — | `ods.i4.sign`, `ods.i4.keypoints`, `ods.i4.facial_marker` |
| I5 fala | **fora** (comentado no compose) | — | — | `ods.i5.transcript` |
| I6 QR | build `inf_a2/` | contínuo | vídeo de QR do A2 em laço | `ods.i6.code_read` |
| I7 placas | build `inf_a8/` | contínuo, detector na GPU | `cam0.mp4` em laço, no ritmo do vídeo | `ods.i7.plate_read` |
| I8 peças | build `inf_a1/` | contínuo, a cada 60 s | 4 eventos de exemplo do próprio I8 (sem modelo no repo) | `ods.industria.defeito_classificado` |
| I9 EPI | `i9` (aqui) | contínuo | `ods.i1.detections` (I1 com a equipe VER3/VER6) | `ods.i9.ppe_compliance` |

Commits no `builds/inf/inf.env`: I3 `0a7f944` e I9 `249ac83` (27/11: Dockerfile da equipe, python
3.12, usuário `nobody`, ingestão em lotes). Os do I1, I2, I6, I7 e I8 são os do `.env` de cada build da
nuvem.

**Por que o I3 continua sob demanda:** é um artefato, não um fluxo. A calibração é publicada uma vez
por câmera e versão, e os consumidores leem a última do tópico (o A5 lê a cauda de
`ods.i3.calibration`). Rodar de novo só reanuncia.

**Por que o I1 continua sob demanda:** o A4 comanda o I1 (`START`/`HEARTBEAT`/`STOP`). O orquestrador
roda um modelo por vez; uma sessão contínua de uma equipe deixaria as outras sem I1. Veja a lacuna do
A3 e do A5 em `situacao_componentes.md`.

## 2. Antes de subir

```bash
cd /opt/ods/p3 && git pull
df -h /                                   # a inf só constrói 2 imagens (I3, I9)
builds/i1/i1.sh parar                     # o I1 permanente fica parado
cd builds && ./ods.sh trocar inf          # sobe inf_a4, inf_a1, inf_a2, inf_a8 e a inf
```

- **Disco:** com as quatro builds da nuvem, a placa guarda as imagens do I1 (4,5 GB), I7 (1,9 GB), I6,
  I8, I2, I3 e I9. A imagem antiga `ods-i9:8ae3933…` fica órfã depois da troca de commit (o
  `limpar.sh` só conhece a do `.env`): `docker image rm ods-i9:8ae3933a3d3fa840a3ddfce0a3b8972d3ca0c59f`.
  Os volumes antigos do I7 da `inf` (`ods-inf_i7-saidas`, `ods-inf_i7-cache`) também ficam: remova à
  mão se quiser o espaço.
- **Mesmo Kafka:** o `inf.sh` lê o broker dos containers do I1, I6, I7 e I8 e avisa se algum usar outro.
- **Memória:** o I1 e o I7 da `inf_a8` usam a GPU ao mesmo tempo (TensorRT, RAM dividida). O teste marca
  `T-I1M` se o I1 reiniciar ou der `OUT_OF_MEMORY`. Se der, esvazie o cache de páginas
  (`sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'`).

## 3. Subir e testar

```bash
cd /opt/ods/p3/builds/inf
./inf.sh status       # containers daqui e das 4 builds da nuvem
./inf.sh testar       # → resultados/aceite-inf-<data>.txt
```

O `testar` conta as mensagens de cada tópico, pede 150 quadros do VER3 ao I1 e roda o I3. Depois
espera, juntas, as mensagens novas do I1, do I2, do I9 e dos contínuos da nuvem que estão rodando,
por até `INF_ESPERA_NUVEM_S` (420 s, uma volta do `cam0.mp4` com a pausa), e conta de novo.

### Resultado esperado

| Item | Esperado | Observação |
|---|---|---|
| T-I1, T-I2, T-I9 | PASSOU | O I1 com `app-epi` no `epi.mp4`; o I2 e o I9 consomem as detecções |
| T-I1M | PASSOU | Sem reinício nem `OUT_OF_MEMORY` no I1 durante o teste |
| T-I3 | PASSOU | Rodar de novo só reanuncia (`artifact.published`); `calibration` pode não crescer |
| T-I4, T-I5 | AVISO | Fora da build |
| T-I6 | PASSOU | I6 da `inf_a2`: uma leitura por volta do vídeo do A2. FALHOU se a `inf_a2` não estiver de pé |
| T-I7 | PASSOU | I7 da `inf_a8`: leituras novas e `artifact_version` `-fp16` no log dele. FALHOU sem leitura ou em CPU |
| T-I8 | PASSOU | I8 da `inf_a1`: 4 eventos a cada 60 s |

### Para conferir cada um à mão

```bash
./inf.sh contar                 # mensagens por tópico
./inf.sh i1 VER5 50             # placas no cam0.mp4 (I1) → ods.i1.detections e ods.i2.tracks
../inf_a8/inf_a8.sh placas      # leituras do I7; ../inf_a2/inf_a2.sh status, ../inf_a1/inf_a1.sh status
alias dc='docker compose --env-file inf.env $( [ -f inf.local.env ] && echo --env-file inf.local.env )'
dc logs --tail 30 i9
```

## 4. Suítes de teste das equipes nas imagens da build

O `./inf.sh testar` confere o Kafka. As suítes dos repositórios rodam à parte, dentro das imagens
exatas da build (lidas do `docker compose config`; na `inf`, desde 27/11/2026, as do I1/I2, I6, I7 e
I8 vêm das builds `inf_a4`, `inf_a2`, `inf_a8` e `inf_a1`, com os commits delas), sem alterar imagem
nem código:

```bash
cd /opt/ods/p3/validacao/inf
./testar-inf-repos.sh              # todos (o I1 pelo validacao/i1/testar-i1-servico.sh, na GPU)
./testar-inf-repos.sh --sem-i1     # sem o I1
./testar-inf-repos.sh i2 i9        # só alguns
```

| Item | Suíte | Como roda | Esperado |
|---|---|---|---|
| R-I1 | `I1/tests` + CMD da imagem | `validacao/i1/testar-i1-servico.sh` (build `i1`) | PASSOU (Jetson 24/11: 45 de 46, o `test_05` precisa do `ultralytics`; CMD com `-fp16`) |
| R-I2 | `I2/tests` (unittest) | do clone por volume (o `.dockerignore` do I2 tira os testes da imagem) | PASSOU (Jetson 24/11: 35 OK) |
| R-I3 | `I3/tests` (unittest) | testes e `dados/` do clone por volume (idem) | PASSOU (Jetson 24/11: 33 OK) |
| R-I4 | `tests/` (pytest) (I4 fora da build) | do clone por volume; `pytest` instalado no container (precisa de rede) | Jetson 24/11: 74 de 77; os 3 que gravam parquet falham: o pip instala o `pyarrow` 26, que exige numpy 2, e o I4 fixa numpy < 2 (não afeta o ao vivo; recado à INV-2) |
| R-I6 | `DetectorQR/test_i6.py` (unittest, desde 25/11) | do clone por volume na imagem `ods-i6` da `inf_a2` (a imagem só leva o `leitor.py`) | PASSOU (notebook 27/11: 18 OK; ainda não rodado na placa) |
| R-I7 | — | a `main` do I7 não tem suíte | AVISO |
| R-I8 | contrato e publicador (pytest) | comando padrão da imagem `ods-i8-publisher` | PASSOU (Jetson 24/11: 139 passed) |
| R-I9 | `I9/tests` (unittest) | do clone por volume | PASSOU (Jetson 24/11: 130 OK com o `8ae3933`; notebook 27/11: 138 OK com o `249ac83`) |

O que vem do clone tem de estar no commit do `inf.env` (o script confere; outra build pode ter
movido o clone compartilhado). Evidência da 1ª execução: `evidencias/inf-repos-20261124-2228.txt`.

Todas rodam com `--network none` (nada vai para o Kafka), menos a do I4. Relatório em
`validacao/inf/resultados/inf-repos-<data>.txt`; copie para `evidencias/` o que for evidência.

## 5. Riscos conhecidos (primeira construção na placa)

- **I9 (`249ac83`):** primeira construção com o Dockerfile da equipe (python 3.12-slim, usuário
  `nobody`). Imagem pequena; a antiga (`8ae3933`) fica órfã.
- **I1 e I7 juntos na GPU:** desde 27/11 o I7 da `inf_a8` roda o tempo todo, e o I1 carrega a engine
  quando chega um pedido. Na placa, em 27/11, os dois conviveram com ~3,8 GB livres.
- **I3:** Python 3.14 e `opencv-python-headless` 5.0 (há roda aarch64 no PyPI).

## 6. Remover

```bash
./limpar.sh               # containers (volumes ficam)
./limpar.sh --imagens     # também as imagens (as que outra build usa ficam com --manter <app>)
./limpar.sh --tudo        # também volumes (pede "inf") e clones exclusivos
```

As builds da nuvem (`inf_a1`, `inf_a2`, `inf_a4`, `inf_a8`) e o vídeo antigo `VIDEO_DIR/inf-qr.mp4` não saem.

## 7. Guardar as imagens no notebook

Roda **no notebook**, não na placa, por `ssh`, sem gravar arquivo no disco da placa. É o mesmo molde do
`builds/inf_a4/guardar-no-notebook.sh`.

```bash
cd ~/Documents/GitHub/p3/builds/inf
./guardar-no-notebook.sh                        # ~/ods-imagens/inf-AAAAMMDD-HHMM/
JETSON=ods@200.17.66.56 ./guardar-no-notebook.sh --comprimir-na-placa   # de fora do laboratório
```

- **Imagens:** `ods-i3` e `ods-i9`, nos commits do `inf.env` (desde 27/11/2026).
- **Fica de fora:** o I1/I2, o I6, o I7 e o I8, que são das builds da nuvem: guarde cada uma com o
  `guardar-no-notebook.sh` dela (a engine do I7 vai no da `inf_a4`); o `cp-kafka`, que é pública.
- **O `ods-i3`** é a mesma imagem da `inf_a4` e vai nas duas pastas.
- **Antes de rodar:** o p3 da placa precisa estar no mesmo commit, porque o script confere os `*_REF`.
  O I3 só existe na placa depois do primeiro `./inf.sh testar` ou `./inf.sh i3`.

Para carregar de volta, ainda sem script próprio: entre na pasta criada, confira com
`sha256sum -c SHA256SUMS` e rode `zstd -dc imagens.tar.zst | ssh ods@172.18.4.56 docker load`. Antes,
confira o disco da placa: `df -h /`.
