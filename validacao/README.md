# Validação de aplicações na Jetson

Esta pasta reúne as validações.

## Objetivo

Testar as aplicações das outras equipes **no nível do sistema**: confirmar que elas rodam na Jetson de forma estável, dentro do orçamento de recursos, sem deixar resíduos e de acordo com os padrões definidos para o ambiente.

## Níveis de teste

| Nível | Quem faz | O que verifica |
|---|---|---|
| Código | Equipe da aplicação | Lógica interna, funções e regras de negócio |
| **Sistema (esta pasta)** | **Equipe de Sistema** | Execução na Jetson: contêineres, recursos, portas, persistência, partida e reinício, e o fluxo principal pela API |

## Como a pasta está organizada

```
validacao/
├── README.md                      <- este arquivo
└── a8/
    ├── README.md                  <- o que é a validação do A8 e como executá-la
    ├── RELATORIO-VALIDACAO.md     <- o que é cobrado, o que foi testado, por quê, como e a conclusão
    ├── validar-a8-fluxo.sh        <- fluxo completo de ponta a ponta (escreve dados de teste e limpa)
    └── evidencias/                <- saídas das execuções, com a data no nome
```

Cada nova aplicação ganha uma pasta própria, com a mesma estrutura da `a8/`.

## Critérios comuns de sistema

Estes critérios valem para toda aplicação. Os critérios **funcionais** (F) dependem de cada aplicação e são definidos no relatório dela.

| ID | Critério | Como verificar |
|---|---|---|
| S1 | Contêineres de pé e saudáveis, sem reinícios inesperados nem falta de memória | `docker ps`, `docker inspect` |
| S2 | Consumo dentro do orçamento (v0 da equipe: até 2.500 MB por serviço e 5.150 MB no total) | `docker stats --no-stream`, `free -m` |
| S3 | Apenas as portas necessárias expostas | `ss -tlnp` na Jetson e `nc` a partir de outra máquina |
| S4 | Dados importantes em volume (sobrevivem à recriação do contêiner) | `docker inspect` (campo `Mounts`) |
| S5 | Reinício automático e ordem de partida definidos | Política de reinício e teste de queda controlado |
| S6 | Imagens seguem o padrão de nomes da equipe (versão e ID de build; sem `latest`) | `docker images` |
| S7 | Uso de disco dentro da política de armazenamento | `df -h /`, `docker system df` |
| S8 | Segredos fora do repositório e das imagens | Revisão do compose e dos Dockerfiles |
| S9 | Logs sem erros recorrentes | `docker logs` |

Critérios funcionais típicos: F1 aplicação responde e enxerga suas dependências; F2 banco com o esquema esperado; F3 fluxo principal de ponta a ponta; F4 rotas protegidas e validações respondem como esperado; F5 os testes não deixam resíduo.

## Convenções dos scripts

- Script que grava usa **dados claramente falsos** (e-mails `@teste.invalid`, documentos fictícios) e **apaga o que criou**, inclusive se forem interrompidos.
- O **código de saída** é o número de falhas: `0` significa que tudo passou.
- Cada linha do resultado começa com `OK`, `FALHA` ou `AVISO`.
- O resultado é gravado em `evidencias/`, com a data no nome do arquivo.
- 
## Aplicações

| Aplicação | Pasta | Situação | Relatório |
|---|---|---|---|
| A8 | [`a8/`](a8/) | Validação funcional concluída;  | [`a8/RELATORIO-VALIDACAO.md`](a8/RELATORIO-VALIDACAO.md) |

## Pré-requisitos para executar

- Executar **na própria Jetson** (os scripts usam `localhost`).
- `bash`, `curl`, `python3` e `docker` (utilizável sem `sudo` pelo usuário).
- Contêineres da aplicação em execução.
- Aviso prévio os testes de fluxo escrevem no banco (em dados de teste que são removidos ao final).

