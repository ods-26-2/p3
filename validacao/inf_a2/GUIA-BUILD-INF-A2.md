# Build "inf_a2": I6 contínuo para o A2 da nuvem

Guia de execução e de teste da build `builds/inf_a2` (P3 · SIS-1), montada em 27/11/2026.

**Estado (27/11/2026):** ainda não rodou na Jetson; foi validada só no notebook:
- `bash -n` e o YAML do compose;
- o código gerado pelo `codigo_a2.py` passou pelo `liberar_entrada` do próprio A2 (`a2` `72cedda`):
  "CPF 12345678909: código válido";
- o vídeo foi gerado com o OpenCV e lido pelo `pyzbar` (o leitor do I6) no ritmo do vídeo: o código
  exato saiu aos 2,1 s de uma volta de 30 s;
- o validador de contrato rodou com o `leitor.py` real do I6 `89143c9`;
- o `inf_a2.sh` rodou contra um `docker` simulado: subida, teste 5/5 e caminhos de falha.

Falta o `docker compose config` real, porque o notebook não tem o plugin.

## 1. Para que serve

O A2 (VER-2, `main` `72cedda`) consome `ods.i6.code_read` do Kafka da nuvem. Para cada leitura, ele:
1. decifra o QR;
2. confere se a data e hora atuais estão dentro da validade;
3. aciona a catraca ligada ao `source_id` (`catracas.json`: `cam0` → `catraca-01`).

A câmera real do P4 não funciona na placa. Por isso o I6 lê em laço um vídeo com um QR que o A2 aceita,
gerado pelo P3.

## 2. As inferências que o A2 usa

| Inferência | Como fica | Por quê |
|---|---|---|
| **I6 QR** | **contínuo** (`i6`), CPU | É a única que o código do A2 consome |
| Outras | fora | O A2 não consome nenhuma outra |

A foto da passagem, que o A2 pede ao S4 por `ods.s4.capture.command`, é de um serviço e não está nesta
build.

## 3. O QR que o A2 aceita

O formato vem de `A2Local/LiberacaoCatraca/interpreta_codigo.py` e de `regras_entrada.py`:

- **Texto do QR:** 32 caracteres hexadecimais, que são 16 bytes cifrados com AES-256-ECB.
- **Chave:** `A2_AES_KEY`, com 32 caracteres. A chave de teste do A2 é `"a"` × 32.
- **Conteúdo dos 16 bytes, em ordem:**
  - base do CPF, com 4 bytes (o A2 calcula os dígitos verificadores);
  - início da validade, com 4 bytes;
  - fim da validade, com 4 bytes;
  - dias da semana, com 1 byte (o A2 ainda não usa);
  - 3 bytes zerados.

Como o P3 monta o QR:
- **Geração:** o `builds/inf_a2/codigo_a2.py` monta os 16 bytes, e o `openssl` da placa cifra. A imagem do
  I6 não tem biblioteca de AES, por isso o OpenCV dela só desenha o QR (`i6/gerar_video_qr_a2.py`).
- **CPF:** de teste, `123.456.789-09`, fictício (`A2_QR_CPF_BASE`).
- **Validade:** começa 1 h antes da geração e dura `A2_QR_VALIDADE_DIAS` (30 dias).
- **Quando o vídeo é gerado de novo:** o `inf_a2.sh` refaz o código e o vídeo se o vídeo faltar, se o CPF
  ou o intervalo mudar, se faltar menos de 1 dia para vencer, ou se a chave mudar. Para forçar:
  `./inf_a2.sh qr`.
- **Chave:**
  - fica no `inf_a2.secrets.env`, fora do Git (copie do `.exemplo`);
  - só o `inf_a2.sh` a usa, na placa, e ela não entra em nenhum container;
  - sem o arquivo, a build usa a chave de teste do A2 e avisa;
  - **se o A2 da nuvem usar outra chave, ele recusa o QR com "Código inválido". Confirme com a VER-2.**

## 4. Como o I6 fica contínuo

- **Laço:** o I6 `89143c9`, em modo teste (`I6_TEST_MODE`), já relê o vídeo em laço.
- **Ritmo:** o `builds/comum/ritmo_video.py`, do P3, faz o I6 ler no ritmo do vídeo. É o mesmo mecanismo
  do I7 da `inf_a8`: troca só o `cv2.VideoCapture` e roda o `leitor.py` como `__main__`. Sem isso, o I6
  leria o vídeo de 30 s em poucos segundos e mandaria uma leitura a cada ~6 s. Para desfazer:
  `I6_TEMPO_REAL=nao`.
- **Leituras:** sai uma por volta, ou seja, uma "pessoa" na catraca a cada `A2_QR_INTERVALO_S` (30 s).
- **`captured_at`:** é a hora da leitura. O A2 descarta leitura pendente com mais de 2 s, e o teste confere
  esse atraso.
- **Imagem:** é a mesma da build `inf` (`ods-i6:89143c9…`). Se já está na placa, nada é construído.

## 5. Subir e testar

```bash
cd /opt/ods/p3 && git pull
cd builds/inf_a2
cp inf_a2.secrets.env.exemplo inf_a2.secrets.env   # opcional: a chave do A2 da nuvem (VER-2)
cd .. && ./ods.sh trocar inf_a2                   # mantém a inf_a4 e a inf_a8
cd inf_a2 && ./inf_a2.sh status
./inf_a2.sh testar                                # → resultados/aceite-inf_a2-<data>.txt
```

### Resultado esperado do `testar`

| Item | Esperado | O que confere |
|---|---|---|
| T-I6C | PASSOU | O container está `running` e não reiniciou durante o teste |
| T-I6 | PASSOU | Há leituras novas em `ods.i6.code_read` com `source_id` `cam0` (espera até 90 s) |
| T-I6Q | PASSOU | O código lido decifra com a chave e está dentro da validade, pelas regras do A2 |
| T-I6T | PASSOU | O atraso entre captura e publicação é de até 2 s, o `max_pending_age` do A2 |
| T-C1 | PASSOU | O contrato, conferido com o `validar_evento_i6` do próprio I6, dentro da imagem dele |

O teste prova a leitura e as regras de validade, mas não a catraca. Ela fica no A2 da nuvem, e a decisão
aparece no log dele: "Código válido." ou "Código inválido.".

## 6. Guardar no notebook e subir de lá

Os dois comandos rodam no notebook, pelo mesmo molde da `inf_a8`, só que sem engine:

```bash
cd ~/Documents/GitHub/p3/builds/inf_a2
./guardar-no-notebook.sh                    # ~/ods-imagens/inf_a2-AAAAMMDD-HHMM/ (imagem ods-i6)
./subir-do-notebook.sh [pasta]
```

A chave e o vídeo não vão para a pasta: o vídeo é refeito na subida.

## 7. Remover

```bash
./limpar.sh                         # containers
./limpar.sh --imagens --manter inf  # também a imagem, se a build inf não a usar
```

O vídeo do QR (`VIDEO_DIR/a2-qr.mp4` e `a2-qr.codigo`) fica. Ele é do P3 e não tem a chave.
