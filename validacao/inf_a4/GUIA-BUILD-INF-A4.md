# Build "inf_a4": só I1, I2 e I3 na Jetson

Guia de execução e de teste da build `builds/inf_a4` (P3 · SIS-1). Montada em 25/11/2026 com o nome
`inf_restrita`; renomeada para `inf_a4` em 26/11/2026, por ser a camada 1-2 do A4 (o A4, o S1 e o I3 de
registro ficam na nuvem). Relatórios anteriores à renomeação se chamam `aceite-inf_restrita-*`.

**Estado (25/11/2026):** na Jetson, com o Kafka **da placa** (1ª versão), `./inf_a4.sh testar`
PASSOU 10, FALHOU 0, AVISO 0 (`resultados/aceite-inf_restrita-20261125-161228.txt`). Depois, a pedido do
usuário, a build passou para o **Kafka da nuvem** (o container `kafka` da placa só precisa continuar
rodando): essa versão foi validada só fora da placa. Antes, a 1ª versão foi validada fora da placa: `docker compose config` com os clones reais (v2.32.4),
`bash -n`, `shellcheck`, os scripts contra um `docker` simulado (sucesso e falha) e o validador de
contrato contra os exemplos válidos e inválidos dos três repositórios. As suítes do I2 (35) e do I3 (33)
passaram no notebook (Python 3.14, o da imagem), nos commits fixados. **Ainda não rodada na Jetson.**

## 1. O que sobe

| Inferência | Serviço | Como roda | Entrada | Saída (tópico) |
|---|---|---|---|---|
| I1 detecção | `i1` | contínuo, GPU (TensorRT via P2), orquestrador **desta build** | `./inf_a4.sh i1 [EQUIPE] [QUADROS]` → `ods.i1.command`; lê `<EQUIPE>.mp4` da pasta original `/home/sys2/SIS-2/videos` | `ods.i1.detections` |
| I2 rastreio | `i2` | contínuo | `ods.i1.detections` | `ods.i2.tracks` |
| I3 calibração | `i3` | `./inf_a4.sh i3` | imagem da quadra do A4 (`dados/` do repositório do I3) | `ods.i3.calibration`, `ods.artifact.published` |
| — | `i1-engine` | one-shot no `subir` | pacotes de `I1_PACOTES` | engines em `/var/lib/ods/engines` |

Commits em `builds/inf_a4/inf_a4.env`, conferidos em 25/11/2026 com `git ls-remote`: são o
HEAD mais novo de cada repositório.

| Repositório | Branch | Commit | Observação |
|---|---|---|---|
| `i1` | `develop` (decisão de 14/11) | `3b2a9cc` (20/11) | mais nova que a `main` e todas as `feat/*` |
| `i2` | `main` | `5283d60` (05/11) | única branch |
| `i3` | `main` | `0a7f944` (25/11) | única branch; só documentação desde o `c3d876e` |

## 2. Decisões

- **Kafka da nuvem** (`34.66.235.91:9093`), a comunicação principal, como as aplicações. "Manter o
  Kafka local" (usuário, 25/11) quer dizer **manter o container `kafka` da placa rodando**: o `subir`, o
  `testar` e o `status` conferem e avisam se ele estiver parado (a build nunca o para; religar é com o
  grupo dono: `docker start kafka`). Para usar o broker da placa só nesta Jetson:
  `cp inf_a4.local.env.exemplo inf_a4.local.env`.
- **I1 próprio:** a mesma imagem do `builds/i1` (`ods-i1-gpu:<I1_REF>`, base `l4t-tensorrt` r10.3.0),
  então não há build nova se ela já existe. Grupo de consumo próprio (`ods-i1-inf-a4`).
- **Dois orquestradores no mesmo broker não podem:** atenderiam o mesmo pedido e disputariam a GPU
  (7,4 GB divididos com a CPU). Se o I1 permanente estiver de pé no **mesmo** Kafka (com os dois na
  nuvem, o normal), o `subir` e o `testar` recusam: pare-o com `../i1/i1.sh parar` enquanto usa esta
  build. Em brokers diferentes, só avisa da memória.
- **Mínimo pelo código:** só I1, I2 e I3. Sem P4 (o orquestrador lê os vídeos das equipes; a
  memória compartilhada do P4 de outra build continua ligada por `ipc: host` + `I1_P4_DIR`).

## 3. Dependências pela arquitetura (6c), lidas nos repositórios

| Componente | Depende de | Como entra na build |
|---|---|---|
| I1 | **P2** (runtime de aceleração) | biblioteca dentro da imagem: wheel `p2 0.2.0a1 [trt,cpu]` do `Dockerfile.jetson` do I1 (existe a `v0.2.0a3`; a troca é do MOD-1) |
| I1 | **B5** (modelos) | os pacotes vêm na própria develop do I1 (`I1/artifacts`: `app-plates 1.0.0`, `app-epi 1.0.0`, `app-industry 1.0.0`, `app-sports 1.2.0`). A `main` do B5 (04/11) só tem `app-plates` (mesmo ONNX, sha256 `b698a519…`) e `app-epi` |
| I1 | **P4** (vídeo) | opcional; sem P4 (pedido sem `source`), `<EQUIPE>.mp4` da pasta original do código, `/home/sys2/SIS-2/videos` (da SIS-2, nesta placa), montada **só leitura** no mesmo caminho (desde 25/11). Vídeos do P3 (`assets/`) em `/videos-p3`, por `"source": "/videos-p3/<EQUIPE>.mp4"` (VER1, VER3, VER6 não estão na pasta da SIS-2) |
| I2 | I1 (`ods.i1.detections`) | o I1 desta build |
| I3 | — (imagem e padrão do chão) | `dados/` do clone, por volume (o `.dockerignore` do I3 tira `dados/` da imagem) |
| testes | B1 (schemas) | o schema de cada tópico que vem no **próprio repositório produtor** (`schemas/`) |

## 4. Uso na Jetson

```bash
cd /opt/ods/p3 && git pull
cd builds/inf_a4
../i1/i1.sh parar            # se o I1 permanente estiver de pé no mesmo Kafka (nuvem)
./inf_a4.sh            # confere a placa (GPU, Kafka da nuvem, container kafka local, I1 permanente), sobe i1 + i2
./inf_a4.sh status
./inf_a4.sh i1 INV1 150    # pedido ao I1 desta build
./inf_a4.sh i3             # calibração da quadra
./inf_a4.sh contar
./inf_a4.sh log i1
./inf_a4.sh parar          # down sem -v
./limpar.sh --help
```

Pela orquestração: `../ods.sh trocar inf_a4` (remove as outras builds de aplicação; o I1 permanente
fica e a imagem dele também).

### 4.1 Guardar no notebook e subir de lá (sem reconstruir)

Os dois scripts rodam **no notebook**, dentro do clone do p3, e falam com a placa por `ssh` (uma senha
só). Nada comprimido é gravado no disco da placa: o `docker save` sai pelo ssh e o `docker load` lê
pelo ssh. O p3 do notebook e o da placa têm de estar no mesmo commit (os scripts conferem os `*_REF`).

```bash
cd ~/Documents/GitHub/p3/builds/inf_a4
./guardar-no-notebook.sh            # ~/ods-imagens/inf_a4-AAAAMMDD-HHMM/: imagens.tar.zst, engines.tar.zst,
                                    # manifesto.txt, inf_a4.env, SHA256SUMS (--sem-engines: só imagens)
./subir-do-notebook.sh [pasta]      # confere a pasta e o disco da placa, carrega só as imagens e engines
                                    # que faltam e roda ./inf_a4.sh subir lá (--sem-subir: só carrega)
```

- Imagens: `ods-i1-gpu`, `ods-i2` e `ods-i3` nos commits do `.env`. O `cp-kafka` não vai (é a mesma
  imagem do Kafka da turma, que fica na placa).
- Engines: as pastas de `I1_PACOTES` em `I1_ENGINES_DIR`, lidas e gravadas por um container da imagem
  do I3 (podem ser só do root). Valem só para esta placa (mesmo TensorRT); o `i1-engine` recompila a que
  não carregar.
- Disco: o `subir` exige livre na placa o tamanho do tar mais `MIN_LIVRE_GB` (4). É uma estimativa por
  cima (o `docker load` pula camadas que já existem); `FORCAR=1` ignora a conta.
- **De fora do laboratório** (rede lenta): `--comprimir-na-placa` no `guardar` e `--descomprimir-na-placa`
  no `subir`. A compressão passa para a placa (zstd se houver, senão gzip, com `nice 19`), e pela rede
  vai o tar comprimido, não o tar cru. Continua sem arquivo no disco da placa; a pasta no notebook é
  sempre `.zst`. O endereço vem de `JETSON` (ex.: `JETSON=ods@200.17.66.56`, se o ssh da placa estiver
  aberto para fora). Na rede do laboratório não precisa: comprimir no notebook é mais rápido.
- Variáveis: `JETSON` (padrão `ods@172.18.4.56`), `P3_JETSON` (`/opt/ods/p3`), `DESTINO` (`~/ods-imagens`).
- Validado só no notebook, contra `ssh` e `docker` simulados (26/11/2026): guardar, subir, segunda subida
  sem nada a carregar, commit diferente, placa sem a build, imagem ausente, pasta corrompida e disco
  insuficiente. Falta rodar com a placa.

## 5. Testes

### 5.1 `./inf_a4.sh testar` (cadeia e contrato pelo Kafka)

Pede ao I1 a equipe `INF_I1_EQUIPE` (padrão `INV1`, 150 quadros: a bola aparece a partir do quadro ~120)
com um `source_id` só do teste, roda o I3, espera a sessão do I1 terminar, lê as mensagens novas de cada
tópico (offset de antes do teste) e valida cada uma com o schema do repositório produtor, **dentro da
imagem dele** (`contrato/validar.py`). Só conta as mensagens do `source_id` do teste: o Kafka da placa é
compartilhado.

| Item | Passa quando |
|---|---|
| T-I1 | chegaram detecções do `source_id` do teste |
| T-I1S | o log do I1 tem `Sessão '<EQUIPE>' encerrada` em até 5 min |
| T-I1G | `artifact_version` único terminando em `-fp16` (TensorRT na GPU) |
| T-I1M | sem reinício do container nem `OUT_OF_MEMORY` no log |
| T-I2 | chegaram trilhas do mesmo `source_id` |
| T-I3 | o I3 terminou com 0 e houve `ods.artifact.published` novo |
| T-C1 | `ods.i1.detections` válido no schema do I1 |
| T-C2 | `ods.i2.tracks` válido no schema do I2 |
| T-C3 | `ods.i3.calibration` (`source_id` `inf-a4-quadra`) válido no schema do I3 |
| T-C4 | `ods.artifact.published` novo válido no schema do I3 |

Relatório: `builds/inf_a4/resultados/aceite-inf_a4-<data>.txt`; mensagens lidas, offsets e
log do I1 na pasta de mesmo nome.

### 5.2 `./inf_a4.sh repos` (suítes das equipes)

`validacao/inf/testar-inf-repos.sh --build inf_a4 [i1 i2 i3]`: roda as suítes dos repositórios nas
imagens desta build, no commit fixado.

| Item | O que roda |
|---|---|
| R-I1 | `validacao/i1/testar-i1-servico.sh --build inf_a4`: `I1/tests` dentro do serviço `i1` desta build (GPU) e o `CMD` do `Dockerfile.jetson` (espera `-fp16`). O `test_05` precisa do `ultralytics`, ausente na imagem Jetson: erro esperado |
| R-I2 | `I2/tests` do clone por volume na imagem `ods-i2`, `--network none` |
| R-I3 | `I3/tests` e `dados/` do clone por volume na imagem `ods-i3`, `--network none` |

Resultado: `validacao/inf_a4/resultados/inf_a4-repos-<data>.txt`.

**Resultado esperado** (pelas execuções da Jetson em 24/11 com as mesmas imagens): R-I1 45/46 (só o
`test_05`), R-I2 35 OK, R-I3 33 OK.

## 6. Disco e memória

- Nada novo a construir se `ods-i1-gpu`, `ods-i2` e `ods-i3` desses commits já estão na placa (a `inf` e o
  `i1` usam os mesmos).
- `./limpar.sh --imagens` não remove a `ods-i1-gpu` (é do I1 permanente) nem as engines e os vídeos.
- Com o I1 permanente também de pé (em outro broker), dois orquestradores dividem a GPU: evite pedidos
  simultâneos nos dois.
