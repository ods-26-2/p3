# Build "inf_a8": I7 contínuo para o A8 da nuvem

Guia de execução e de teste da build `builds/inf_a8` (P3 · SIS-1), montada em 27/11/2026.

**Estado (27/11/2026):** na Jetson, com o Kafka da nuvem e o `cam0.mp4`, `./inf_a8.sh testar` PASSOU 5,
FALHOU 0, AVISO 0 (9 placas válidas, detector `-fp16`, captura → publicação em 0,1 s, sem reinício):
`evidencias/aceite-inf_a8-20261127-020650.txt`. Antes, validada fora da placa: `bash -n`, YAML, o ritmo do `i7_continuo.py` com um
`cv2` falso, o validador com eventos montados pelo publicador do próprio I7, e os scripts contra um
`docker` simulado (subida, teste nos caminhos de sucesso e de falha, `i1`, `status` e a troca no
`ods.sh`). O 1º teste na placa, com o `VER5.mp4`, não publicou nada (placas estrangeiras; ver §3).

## 1. Para que serve

O A8 (VER-5) roda na nuvem. Na `develop` (`f50b5a4`, 26/11) ele consome só `ods.i7.plate_read` do Kafka
da nuvem e aciona a cancela quando a leitura obedece a três condições:
- `source_id` é `cam-entrada` ou `cam-saida`;
- `captured_at` é recente;
- a confiança é de pelo menos 0,9.

Esta build deixa o I7 de pé na placa. Ele lê o `cam0.mp4` (vídeo do estacionamento da VER-5) em laço,
como se fosse a câmera da entrada, e publica no Kafka da nuvem. A câmera real do P4 não funciona na
placa (27/11/2026).

## 2. O que cada inferência entrega ao A8

| Inferência | Como fica | Por quê |
|---|---|---|
| **I7 placas** | **contínuo** (`i7`), GPU | É o único tópico que o código do A8 consome |
| I1 detecção (VER5, `app-plates`) | sob demanda, pelo I1 da `inf_a4`: `./inf_a8.sh i1 [QUADROS]` | O A8 não consome detecções. O orquestrador carrega um modelo por vez: uma sessão contínua do VER5 deixaria o A4 sem I1, e um segundo orquestrador disputaria a GPU |
| I2 rastreio | vem junto com o I1 da `inf_a4` | Só tem entrada quando o I1 detecta |
| I3 calibração | fora | Zonas do A8 em pixels; não há dado de calibração do estacionamento |
| I6 QR | fora | Opcional na 6c; o A8 não lê QR |

Para a cadeia da 6c (I1 → I2 → S1 → S5), use o `./inf_a8.sh i1`. O S1 e o S5 do A8 não estão compostos.

## 3. Como o I7 fica contínuo

O I7 `1441bbb` não tem modo laço: com `--video`, ele termina no fim do arquivo. Tudo é feito pelo P3, sem
alterar o código do I7.

- **Laço:** o comando do serviço toca o vídeo, espera `I7_PAUSA_S` (30 s) e toca de novo. Se o I7 sair com
  erro, o laço sai com o mesmo código e o Docker reinicia o container (`restart: unless-stopped`). Por
  isso o `RestartCount` conta só as falhas.
- **Ritmo do vídeo:** com `I7_TEMPO_REAL=sim`, o `builds/inf_a8/i7_continuo.py` faz o I7 ler cada quadro
  no instante dele no vídeo. Assim os carros chegam ao A8 no tempo do vídeo, sem rajada. Sem isso, o I7
  processa o mais rápido que consegue. Para desfazer: `I7_TEMPO_REAL=nao` no `inf_a8.local.env`.
- **`captured_at`:** é a hora da leitura do quadro, que é o próprio I7 que define. Por isso a cancela do
  A8 não recusa o evento por ser antigo.
- **Repetição:** cada volta é um processo novo. As mesmas placas voltam a ser publicadas a cada volta,
  e o A8 vê os mesmos carros chegando de novo.
- **Disco:** as saídas (CSV e mosaicos) ficam em `/saidas/<vídeo>` e cada volta sobrescreve a anterior,
  então não crescem.
- **Imagem e engine:**
  - a imagem é a mesma da build `inf` (`ods-i7-gpu:1441bbb…`, mesma receita): se já existe na placa,
    nada é construído;
  - a engine é a `app-plates-1.0.0` do I1, que a `inf_a4` compila em `/var/lib/ods/engines`.
- **Vídeo:** é o `/var/lib/ods/videos/cam0.mp4`, a pasta de vídeos do P3, montado só para leitura e
  sem criar a pasta. **Não use o `VER5.mp4` da SIS-2 no I7.** No 1º teste na placa (27/11) o I7
  detectou as placas, mas elas não são brasileiras (ex.: `34A36837`): todas saíram "Inválida" e
  nenhuma foi publicada. O VER5.mp4 serve ao I1 (`./inf_a8.sh i1`).

## 4. Subir e testar

```bash
cd /opt/ods/p3 && git pull
df -h /
cd builds
./ods.sh trocar inf_a8      # ou: cd inf_a8 && ./inf_a8.sh
cd inf_a8
./inf_a8.sh status
./inf_a8.sh placas          # últimas leituras no log
./inf_a8.sh testar          # → resultados/aceite-inf_a8-<data>.txt
```

- **Convivência:** a `inf_a4` (A4 da nuvem) e a `inf_a8` convivem. `./ods.sh trocar inf_a8`,
  `trocar inf_a4` ou `trocar inf` mantêm as duas. Trocar para uma aplicação (`a1` … `a8`) derruba as
  duas, com aviso.
- **Engine:** se faltar, a subida para e manda compilar com `../inf_a4/inf_a4.sh engines`.
- **Memória:** o I7 contínuo divide a GPU e a RAM com o orquestrador do I1 da `inf_a4`. No teste da `inf`
  de 27/11 sobraram ~3,9 GB com os dois, mas lá o I7 rodou por poucos segundos.

### Resultado esperado do `testar`

| Item | Esperado | O que confere |
|---|---|---|
| T-I7C | PASSOU | O container está `running`, sem reinício nem `OUT_OF_MEMORY` durante o teste |
| T-I7 | PASSOU | Leituras novas em `ods.i7.plate_read` com `source_id` `cam-entrada`. Espera até `I7_TESTE_ESPERA_S`, 420 s: no ritmo do vídeo, os carros só passam em certos trechos |
| T-I7G | PASSOU | O `artifact_version` contém `-fp16` (detector no TensorRT). Em CPU seria `-fp32` |
| T-I7T | PASSOU | Captura → publicação em até 120 s (a cancela do A8 recusa evento antigo) |
| T-C1 | PASSOU | O contrato, conferido com o `validar_evento` do próprio I7, dentro da imagem dele |

## 5. Guardar no notebook e subir de lá

Os dois scripts rodam **no notebook**, por `ssh`, sem gravar arquivo no disco da placa. É o mesmo molde
da `inf_a4`.

```bash
cd ~/Documents/GitHub/p3/builds/inf_a8
./guardar-no-notebook.sh                    # ~/ods-imagens/inf_a8-AAAAMMDD-HHMM/
JETSON=ods@200.17.66.56 ./guardar-no-notebook.sh --comprimir-na-placa   # de casa
./subir-do-notebook.sh [pasta]              # confere commit e disco, docker load, engine e ./inf_a8.sh subir
JETSON=ods@200.17.66.56 ./subir-do-notebook.sh --descomprimir-na-placa
```

A pasta guarda:
- a imagem `ods-i7-gpu`;
- a engine `app-plates-1.0.0`, que também vai na pasta da `inf_a4`;
- o manifesto e o `SHA256SUMS`.

## 6. Remover

```bash
./limpar.sh                     # containers (volumes ficam)
./limpar.sh --imagens --manter inf   # também a imagem, se a build inf não a usar
./limpar.sh --tudo              # também volumes (pede "inf_a8") e o clone do i7, se só esta build o usar
```

O `limpar.sh` não mexe na engine do I1, nos vídeos da SIS-2 nem no container `kafka`.
