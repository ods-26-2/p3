# Validação de Aplicações na Jetson

Este diretório centraliza a homologação de sistemas na plataforma NVIDIA Jetson, garantindo estabilidade, conformidade de recursos e isolamento de dados.

## Objetivo e Escopo

**A Equipe de Sistema valida a integração com o hardware e o SO.** Esta validação não substitui os testes de desenvolvimento das equipes das aplicações.

| Nível | Responsável | Foco |
|---|---|---|
| Código | Equipe da Aplicação | Lógica interna e regras de negócio. |
| **Sistema** | **Equipe de Sistema** | Contêineres, recursos, portas, persistência, logs e fluxo via API. |

## Organização do Diretório

```text
validacao/
├── README.md                      <- Este arquivo
├── validacao-geral/
│   ├── evidencias/                <- Resultados
│   └── validar-hardware.sh        <- Valida arquitetura, GPU, CUDA, JetPack e memória
└── a8/                            <- Exemplo de estrutura por aplicação
    ├── README.md                  <- Como executar a validação específica
    ├── RELATORIO-VALIDACAO.md     <- Critérios, testes e parecer final
    ├── validar-a8-fluxo.sh        <- Script do fluxo ponta a ponta
    └── evidencias/                <- Logs de execução com data no nome
```
*Cada nova aplicação deve seguir rigorosamente a estrutura da pasta `a8/`.*

## Critérios de Sistema (Comuns a todas as aplicações)

| ID | Critério | Ferramenta |
|---|---|---|
| **S1** | Contêineres estáveis e saudáveis | `docker ps`, `docker inspect` |
| **S2** | Consumo no limite (2.500MB/serviço | 5.150MB total) | `docker stats`, `free -m` |
| **S3** | Apenas portas necessárias expostas | `ss -tlnp`, `nc` |
| **S4** | Persistência de dados em volumes | `docker inspect` (`Mounts`) |
| **S5** | Reinício automático e ordem de partida válidos | Teste de queda controlado |
| **S6** | Imagens com tag de versão (sem `latest`) | `docker images` |
| **S7** | Uso de disco dentro da política | `df -h`, `docker system df` |
| **S8** | Segredos fora do repositório/imagens | Revisão de Dockerfile/Compose |
| **S9** | Logs limpos de erros críticos recorrentes | `docker logs` |

*Os critérios funcionais (F1 a F5) validam a integridade da API, banco de dados e limpeza de resíduos, sendo detalhados no relatório de cada aplicação.*

## Convenções dos Scripts

- **Dados de teste:** Usar dados estritamente fictícios (`@teste.invalid`) e garantir a **limpeza total**, mesmo em caso de interrupção.
- **Códigos de saída:** O retorno do script deve ser o **número exato de falhas** (`0` = sucesso absoluto).
- **Padronização de logs:** Iniciar linhas com prefixos claros: `OK`, `FALHA` ou `AVISO`.
- **Evidências:** Salvar saídas em `evidencias/` seguindo a nomenclatura com data (`nome-fluxo-AAAA-MM-DD.txt`).

## Status das Validações

| Aplicação | Pasta | Situação | Relatório |
|---|---|---|---|
| A8 | [`a8/`](a8/) | Validação funcional concluída | [`a8/RELATORIO-VALIDACAO.md`](a8/RELATORIO-VALIDACAO.md) |

## Pré-requisitos de Execução

1. **Validação de Hardware Concluída:** O ambiente Jetson deve ser previamente validado com sucesso.
   ```bash
   cd validacao-geral/ && ./validar-hardware.sh
   ```
2. **Ambiente Local:** Executar diretamente na Jetson alvo (uso de `localhost`).
3. **Ferramentas:** `bash`, `curl`, `python3` e `docker` configurado para rodar sem `sudo`.
4. **Estado:** Aplicação alvo já em execução antes de iniciar os testes de fluxo.
