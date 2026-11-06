# Validação do A8

Validação do A8 no nível do sistema. O contexto geral está em [`../README.md`](../README.md). O resultado e a análise completa estão em [`RELATORIO-VALIDACAO.md`](RELATORIO-VALIDACAO.md).

**Situação atual:** A validação funcional (fluxo de ponta a ponta e ausência de resíduos no banco) foi concluída com sucesso em 05/11/2026. 

## O que é o A8 (como aparece na Jetson)

| Serviço | Imagem | Porta | Observação |
|---|---|---|---|
| `a8-backend` | `a8-backend` | 3000 | API; o código mostra um módulo Kafka em `backend/src/kafka/validarLeituraPlaca.js` |
| `a8-frontend` | `a8-frontend` | 8081 | Interface web |
| `a8-mysql` | `mysql:8.4` | não publicada | Banco `a8` |
| `kafka` | `confluentinc/cp-kafka:latest` | 9092 e 9093 | Mensageria |

O código-fonte e o `docker-compose.yml` ficam no repositório da equipe do A8. Esta pasta contém **apenas** o necessário para validar.

## O que esta validação verifica

- O backend responde e enxerga o banco.
- O banco `a8` está carregado com as tabelas esperadas.
- O fluxo principal funciona: empresa, login, usuário, veículo convidado e login do usuário.
- Rotas protegidas e validações de entrada respondem como esperado.
- Os testes **não deixam resíduo** no banco.

O que cada teste confirma, e por quê, está no relatório.

## Pré-requisitos

- Executar na Jetson, com os contêineres `a8-backend` e `a8-mysql` em execução.
- `bash`, `curl`, `python3` e `docker` (sem `sudo`).
- No contêiner `a8-mysql`: cliente `mysql` e a variável `MYSQL_ROOT_PASSWORD` definida (a senha nunca aparece nos scripts).
- Banco chamado `a8`, com as tabelas `Empresa`, `Usuario` e `Veiculo_Convidado`.
- A API com as rotas `/api/health`, `/api/login`, `/api/empresas`, `/api/usuarios`, `/api/veiculos-convidados` e `/api/usuarios/empresas`.

Se algum nome for diferente no ambiente, ajuste com variáveis: `API` (padrão `http://localhost:3000`) e `DB_CONTAINER` (padrão `a8-mysql`).

## Como executar


 Fluxo completo: cria empresa, usuário e veículo de teste e apaga tudo

./validar-a8-fluxo.sh

Resultado esperado: `RESULTADO: FUNCIONA (fluxo completo)`.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `validar-a8-fluxo.sh` | Fluxo completo de ponta a ponta com dados de teste, removidos ao final |
| `RELATORIO-VALIDACAO.md` | Critérios cobrados, testes, motivos, procedimento, conclusão e histórico |
| `evidencias/` | Saídas das execuções, com a data no nome |
