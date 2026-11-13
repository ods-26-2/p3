# Teste individual do I1 na GPU (TensorRT via P2)

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
