O A6 está commitado no branch `builds/a6` (commit `262af85`), mas ainda não foi para o GitHub. Para a Jetson receber, posso fazer o mesmo que no A8: juntar ao `main` e enviar.

Entraram a pasta `builds/a6` e o que ela usa e ainda não estava no GitHub: `comum/preparar-codigo.sh`, a biblioteca dos testes (`comum/aceite`), `validacao/a6` e o `fluxo-comum.sh`. As outras apps, o `CLAUDE.md` e os READMEs gerais ficaram de fora.

## O que falta para o A8 funcionar 100%
Considero "100%" o uso real (carro na câmera, cancela física, registro) e o que o plano 6c prevê para o A8. Separei pelo que o P3 resolve e pelo que depende de outras equipes.

### Do P3 (nosso)
1. **Rodar na Jetson o que ainda não rodou:** `./a8.sh placas-video`, `./a8.sh testar` completo, `validar-sistema.sh a8` e o fluxo pela API. Até agora isso foi testado só com simulação.
2. **Um teste que cadastre antes de ler:** o `testar` atual nunca prova a liberação, porque não cadastra veículo.
   - O teste cadastraria pela API empresa, usuário, veículo vinculado e dois convidados (dentro e fora do período).
   - Depois esperaria `liberado`, `negado` e a cancela abrindo e fechando, nas câmeras de entrada e de saída.
   - No fim, apagaria os dados de teste.
3. **Conferir as portas 3000 e 8081 de fora do laboratório.** O Docker publica as portas por cima do firewall (`ufw`).
4. **Marcar a versão validada:** a tag `a8-cadeia-v1` foi proposta e ainda falta você confirmar.

### VER-5 (A8, a aplicação)
5. **Registrar cada acesso** (placa, câmera, decisão e horário). Hoje a decisão só vai para o log: não há histórico, auditoria nem base para cobrança.
6. **Conferência manual para `baixa_confianca`.** Pelos testes da própria equipe, cerca de 26% das leituras caem nesse caso e não existe tela onde alguém libere ou negue.
7. **Regra própria para a saída.** Hoje a saída usa a mesma regra da entrada, então um convidado com período vencido fica preso.
8. **Filtrar por empresa.** Hoje uma placa de um condomínio abre o portão de outro.
9. **Câmeras e cancelas configuráveis** em vez de fixas no código, e **um driver de cancela real** (relé, controladora ou API do fabricante). Hoje a cancela é simulada.
10. **O que o plano prevê e o código ainda não tem:**
    - reserva por evento;
    - regra de vaga livre usando a ocupação do S1;
    - tarifa por tempo de permanência;
    - foto da entrada pelo S4;
    - painel com métricas do S5;
    - zonas reais das vagas (hoje são as de exemplo do P3).
11. **Imagens prontas para produção:** usuário não-root e frontend estático. Hoje o frontend roda o servidor de desenvolvimento do Expo.

### VER-5 (I7, leitura de placas)
12. **Ler os quadros da câmera (P4)** em vez de uma pasta de fotos, que é o que o `placas-video` contorna hoje.
13. **Ligar a leitura ao veículo rastreado** pelo `detection_id` do I1/I2. Assim cada carro gera uma decisão, e não uma por quadro.
14. **Levar para a `main` a versão da `development`**, com o detector rodando via P2.

### Outras equipes da cadeia
15. **SIS-1 (P2):** modelos compilados com TensorRT para o I1 e o I7. Hoje tudo roda em CPU e a GPU fica parada.
16. **SIS-2 (P4):** envelope no formato da 6c (`published_at`, `captured_at`, `sequence`) e um formato de memória compartilhada que o S4 consiga ler.
17. **MOD-2 (S4):** corrigir a data dos clipes, que soma o tempo ligado, e o nome do tópico de resposta.
18. **VER-6 (S2, S1):** o S2 publicar no Kafka (sem ele não há eventos de "vaga ocupada demais") e o S1 esvaziar as zonas no fim da sessão.
19. **INV-1 (I3):** calibrar as câmeras do estacionamento com medidas reais, para as zonas ficarem em metros.
20. **MOD-1 (I1):** corrigir os imports que faltam e o código de saída no fim do vídeo. Hoje o compose contorna os dois.
21. **TRA-1:** o Kafka da turma voltar sozinho depois de reiniciar a placa (`restart`), ter autenticação e parar de mudar de endereço sem aviso.

### Prioridade sugerida
Para o A8 ser usável num portão de verdade, o essencial é:

| Ordem | O que | Itens |
|---|---|---|
| 1º | Teste com cadastro, feito por nós | 2 |
| 2º | Registro de acesso e conferência manual, no A8 | 5 e 6 |
| 3º | Regra de saída, no A8 | 7 |
| 4º | I7 lendo a câmera, no I7 | 12 |
| 5º | Driver de cancela real, no A8 | 9 |
| 6º | TensorRT, no P2 | 15 |

O resto completa o plano 6c, mas não impede o uso básico. Se quiser, começo pelo item 2.

