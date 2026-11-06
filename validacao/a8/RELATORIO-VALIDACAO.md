# Relatório de validação: A8

## 1. Resumo

- **Funcional: concluído com sucesso em 05/11/2026.** O fluxo completo (empresa, login, usuário, veículo convidado, login do usuário) passou em todas as 9 verificações, e os dados do banco ficaram idênticos antes e depois do teste.
 **Conclusão atual:** a aplicação funciona na Jetson.
  
## 2. Escopo

Serviços observados na Jetson:

| Serviço | Imagem | Porta | 
|---|---|---|
| `a8-backend` | `a8-backend` | 3000 | 
| `a8-frontend` | `a8-frontend` | 8081 | 
| `a8-mysql` | `mysql:8.4` | não publicada | 
| `kafka` | `confluentinc/cp-kafka:latest` | 9092 e 9093 | 

## 3. O que a equipe de Sistema cobra da aplicação

O motivo de cada critério.

### Funcionais (específicos do A8)

| ID | Critério | Por quê | Estado |
|---|---|---|---|
| F1 | O backend responde e enxerga o banco | Sem isso nada mais funciona | **OK:** o fluxo só passa se backend e banco funcionam. |
| F2 | Banco `a8` carregado com as tabelas esperadas | Garante que o esquema (`database.sql`) foi aplicado | **OK:** o fluxo consultou `Veiculo_Convidado` com sucesso |
| F3 | Fluxo principal de ponta a ponta | É o uso real da aplicação | **OK** em 05/11/2026 |
| F4 | Os testes não deixam resíduo no banco | Evita poluir um ambiente em uso | **OK:** dados idênticos antes e depois |

## 4. Testes executados e por quê

### 4.1 Fluxo completo (`validar-a8-fluxo.sh`), 05/11/2026 às 22h46 (-03)

Resultado: 9 verificações `OK` e `RESULTADO: FUNCIONA (fluxo completo)`.

| # | Verificação | Esperado | Por que é testado |
|---|---|---|---|
| 1 | Cadastro de empresa | HTTP 201 | Ponto de entrada de todo o fluxo |
| 2 | Login da empresa | HTTP 200 | Autenticação funciona |
| 3 | Recebimento do token | token presente | As rotas seguintes dependem dele |
| 4 | Empresa cadastra usuário | HTTP 201 | Teste de rota protegida e de relacionamento empresa-usuário |
| 5 | Cadastro de veículo convidado | HTTP 201 | Funcionalidade central do A8 |
| 6 | Veículo gravado no banco | 1 registro | Confirma que a API grava de fato, e não só responde 201 |
| 7 | Login do usuário | HTTP 200 | O usuário criado pela empresa consegue entrar |
| 8 | Usuário lista suas empresas | HTTP 200 | Confirma o vínculo entre usuário e empresa |
| 9 | Dados de teste removidos | 0 registros | O teste não deixa lixo |


### 4.2 Análise do esquema e do código

Busca no `database.sql` e no `backend`, sem executar nada:

- Todas as chaves estrangeiras (`Empresa_Usuario`, `Empresa_Adm`, `Veiculo`, `Veiculo_Empresa`, `Veiculo_Convidado`) têm `ON DELETE CASCADE`. Por isso a limpeza do teste (que apaga só `Usuario` e `Empresa`) leva junto os registros dependentes.
- Os pontos de escrita no banco estão nos modelos e controladores (`INSERT INTO` em `Empresa`, `Usuario`, `Empresa_Usuario`, `Empresa_Adm`, `Veiculo`, `Veiculo_Empresa` e `Veiculo_Convidado`).
- O único uso de produtor Kafka encontrado foi em `backend/src/kafka/validarLeituraPlaca.js`. As rotas do fluxo não aparecem publicando mensagens. A busca foi limitada (`producer` e `.send(`), então é um indício, e não uma prova.

### 4.3 Observação do estado dos contêineres

Pelo `docker ps`: os quatro contêineres estavam em execução; o MySQL `healthy`; o backend tinha sido recriado há poucas horas; o frontend e o Kafka tinham sido reiniciados depois do MySQL. Foi uma observação, e não um teste: a causa dos reinícios não foi investigada.

## 5. Como a validação foi feita

### 5.1 Preparação

1. Contêineres do A8 em execução na Jetson.
2. Pré-requisitos conferidos: `bash`, `curl`, `python3`, `docker` sem `sudo`, `mysql` e variável da senha no contêiner, banco `a8` com as tabelas.

### 5.2 Execução
 
 `validar-a8-fluxo.sh` . Cada execução grava a saída em `evidencias/`.

### 5.3 Cuidados com os dados

- Os dados de teste são identificáveis e fictícios: `zz-*@teste.invalid`, CNPJ `99000000000001`, CPF `99999999999`, placa `ABC1D23`.
- O script apaga esses registros antes de começar e ao terminar (inclusive se for interrompido).

### 5.4 Como ler o resultado

Cada linha começa com `OK`, `FALHA` ou `AVISO`. O código de saída do script é o número de falhas (`0` = tudo passou).

## 6. Como a validação é concluída

A validação do A8 é considerada **concluída** quando:

1. Os critérios funcionais estão `OK`;
2. Os critérios de sistema estão `OK` ;
3. Há evidências em `evidencias/` para cada critério;
4. Este relatório está atualizado com a data, a versão validada e o resultado final.

- A URL da API e o nome do contêiner do banco passaram a poder ser trocados por variáveis (`API` e `DB_CONTAINER`).
- No fluxo, as datas do veículo convidado passaram a ser **amanhã** (antes eram fixas em 05/11/2026), para o teste não quebrar se a API passar a rejeitar datas passadas.
- Foi acrescentado o `comparar-banco-antes-depois.sh`, que automatiza a comparação feita manualmente.
