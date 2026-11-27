# Build "inf_a1": I8 contínuo para o A1 da nuvem

Guia de execução e de teste da build `builds/inf_a1` (P3 · SIS-1), montada em 27/11/2026.

**Estado (27/11/2026):** ainda não rodou na Jetson; foi validada só no notebook:
- `bash -n` e o YAML do compose;
- os 4 eventos de exemplo do I8, preparados como o `publicar_exemplos.py` faz, passaram 4 de 4 no
  validador do **próprio A1** (`backend/contracts.py`, contrato `ods.industria.defeito_classificado` 2.0);
- o `inf_a1.sh` rodou contra um `docker` simulado: subida, teste 3/3, teste sem eventos, pedido ao I1
  e `status`.

Falta o `docker compose config` real, porque o notebook não tem o plugin.

## 1. Para que serve

O A1 (VER-1, `main` `5e0f07e`, implantado na GCP com o Kafka da nuvem) consome
`ods.industria.defeito_classificado` 2.0, e ainda o legado `ods.i8.piece_analysis` 1.0. Esta build
mantém um fluxo contínuo de eventos válidos no Kafka da nuvem, para o A1 fazer a triagem.

**Os eventos são SINTÉTICOS.** O I8 (`051851f`) não faz inferência de verdade hoje: a documentação dele
diz que não há imagens nem manifesto real no repositório ("A prova local usa eventos sintéticos, não
inferência real"). Por isso a build roda o publicador **oficial** do I8, que reenvia os 4 eventos de
exemplo dele: CONFORMING, NON_CONFORMING, ANOMALY e UNCERTAIN.
- Cada rodada recebe ids, sessão e horários novos.
- O publicador valida os eventos contra o contrato 2.0 e a taxonomia do A1, e exige confirmação de
  entrega.
- Os eventos saem marcados com `artifact_version` `p3-exemplos-i8`.

## 2. As inferências que o A1 usa

| Inferência | Como fica | Por quê |
|---|---|---|
| **I8 peças** | **contínuo** (`i8`): 4 eventos de exemplo a cada `I8_INTERVALO_S` (60 s) | É a única que o código do A1 consome |
| I1 detecção (VER1, `app-industry`, classe `peca`) | sob demanda, pelo I1 da `inf_a4`: `./inf_a1.sh i1 [QUADROS]`, com o `VER1.mp4` do P3 (`/videos-p3`) | O A1 não consome detecções. O orquestrador atende um modelo por vez (veja a `inf_a8`) |
| P7 pan-tilt | fora | O A1 comanda o P7, mas a SIS-2 não tem Kafka para ele |

## 3. Subir e testar

```bash
cd /opt/ods/p3 && git pull
cd builds && ./ods.sh trocar inf_a1     # mantém a inf_a2, a inf_a4 e a inf_a8
cd inf_a1 && ./inf_a1.sh status
./inf_a1.sh testar                      # → resultados/aceite-inf_a1-<data>.txt
```

A imagem é a mesma da build `inf` e do `a1` (`ods-i8-publisher:051851f…`): se já existe na placa, nada é
construído. A taxonomia vem do clone do A1, no mesmo commit da `inf` (`5d17305`). A taxonomia, os schemas
e o `contracts.py` desse commit são idênticos aos do `5e0f07e`.

### Resultado esperado do `testar`

| Item | Esperado | O que confere |
|---|---|---|
| T-I8C | PASSOU | O container está `running` e não reiniciou durante o teste |
| T-I8 | PASSOU | Chegou pelo menos uma rodada (4 eventos `p3-exemplos-i8`) com as 4 classificações. Espera até 150 s |
| T-C1 | PASSOU | O contrato, conferido pelo validador do **consumidor** (`backend/contracts.py` do A1, com os schemas dele), dentro da imagem do I8 |

O teste prova que os eventos chegam ao Kafka da nuvem num formato que o A1 aceita. A triagem fica no A1
da nuvem e é a VER-1 que confere.

## 4. Guardar no notebook e subir de lá

```bash
cd ~/Documents/GitHub/p3/builds/inf_a1
./guardar-no-notebook.sh          # ~/ods-imagens/inf_a1-AAAAMMDD-HHMM/ (imagem ods-i8-publisher)
./subir-do-notebook.sh [pasta]
```

## 5. Remover

```bash
./limpar.sh                         # containers
./limpar.sh --imagens --manter inf  # também a imagem, se nem a inf nem o a1 a usarem
```
