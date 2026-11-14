# Teste de resistência com `jetson_clocks` (`testar-jetson-clocks.sh`)

**Pergunta:** a Jetson aguenta ficar com os relógios fixos no máximo (`sudo jetson_clocks`) o tempo todo?

**Por que importa:** com `jetson_clocks`, o I1 vai de 25 para 64 quadros/s ([`validacao/i1/evidencias/i1-tempo-real-2026-11-14.txt`](../i1/evidencias/i1-tempo-real-2026-11-14.txt)). Mas a placa é compartilhada, e a decisão vale para todos os grupos.

```bash
cd /opt/ods/p3/validacao/placa
./testar-jetson-clocks.sh                  # 5 min base + 5 min parado + 30 min de carga (~40 min)
./testar-jetson-clocks.sh --carga 60       # carga mais longa, mais perto do equilíbrio térmico
./testar-jetson-clocks.sh --repouso 1 --carga 3    # rodada curta só para conferir o script
```

**O que o teste faz:**
1. **Base:** relógios dinâmicos, como a placa está hoje.
2. **Parado:** `jetson_clocks` ligado, sem carga. Mostra o custo de deixá-lo ligado à toa.
3. **Carga:** `jetson_clocks` ligado com a GPU sem pausa, fazendo inferência do I1 direto pelo P2. É o pior caso, bem mais pesado que o A8 com uma câmera de 10 quadros/s.

Em cada fase, o teste grava o `tegrastats` (potência `VDD_IN`, temperatura `tj`, uso da GPU) e a ventoinha. No fim, ou com Ctrl+C, restaura os relógios guardados com `jetson_clocks --store`.

**Cuidados com a placa:**
- Não para nem recria nenhum container. O Kafka da turma e as builds de pé continuam rodando e entram na medida.
- Precisa de sudo.
- Se o script morrer sem restaurar (por exemplo, queda de energia), o reinício da placa volta aos relógios dinâmicos, porque o `jetson_clocks` não persiste. Para restaurar sem reiniciar: `sudo jetson_clocks --restore resultados/jetson-clocks-<data>/clocks-antes.conf`.

| Item | Confirma |
|---|---|
| J01 | Temperatura máxima sob carga pelo menos 10 °C abaixo do primeiro limite térmico passivo do kernel (onde a placa começa a reduzir os relógios) |
| J02 | Nenhum evento de sobrecorrente (`oc*_event_cnt`): a fonte e o regulador não limitaram a placa |
| J03 | Desempenho estável: no último trecho de 30 s, pelo menos 90% das inferências/s do primeiro. Se cair, houve redução por calor ou por energia |
| J04 | O Kafka da turma continuou de pé |
| J05 | Informativo: quanto potência, temperatura e ventoinha sobem com o `jetson_clocks` ligado sem uso |

**O que o teste não responde:**
- **Desgaste de longo prazo,** que não se mede em uma hora.
- **Outras condições de sala:** vale para a temperatura da sala no dia do teste. Num dia mais quente, a folga do J01 diminui.

**Validação:** só fora da Jetson, contra `tegrastats`, `jetson_clocks`, `sudo` e `docker` simulados e um limite térmico falso (`TERMICO=<pasta>`). Foram simulados três casos:
- **normal:** tudo PASSOU;
- **quente, com queda de desempenho e sem Kafka:** J01 deu AVISO, J03 FALHOU e J04 deu AVISO;
- **interrompido na fase 2:** os relógios foram restaurados.
