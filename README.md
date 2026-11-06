# P3 — Ambiente ODS (Jetson Linux)

Este repositório centraliza os artefatos, scripts de automação, documentações de auditoria e políticas de gerenciamento da plataforma base baseada no ecossistema NVIDIA Jetson (JetPack 6.2.1 / L4T R36.4.7).

---

## 📂 Estrutura do Diretório

Abaixo está o mapeamento completo dos componentes deste repositório e suas respectivas finalidades:

```text
p3/
├── image-base-v1/                     # Artefatos e validações do Sistema Operacional raiz
│   ├── gerar-imagem.sh                # Script Bash que automatiza o backup via SSH com zstd
│   ├── Imagem base v1 do sistema...pdf # Documentação técnica formal do ambiente v1
│   ├── imagem-base-v1.sha256          # Hash oficial para checagem de integridade do arquivo tar.zst
│   ├── manifesto.txt                  # Listagem minuciosa de arquivos inclusos na imagem
│   ├── pacotes-instalados.txt         # Relação completa de pacotes APT/DPKG do sistema de origem
│   ├── pacotes-travados.txt           # Relação de pacotes com hold de versão (evita atualizações acidentais)
│   └── padronizacao/                  # Submódulo para governança e verificação de conformidade
│       ├── evidencias/                # Logs brutos coletados da GPU e do sistema de arquivos
│       │   ├── base-gpu.txt
│       │   ├── gpu-b003.txt
│       │   ├── labels-b003.txt
│       │   ├── linha13-build.txt
│       │   ├── linha13-negativo.txt
│       │   ├── padrao-2026-11-03.txt
│       │   └── padrao-negativo.txt
│       ├── PADRAO-NOMES.md            # Regras e convenções estritas para nomenclatura de logs/arquivos
│       └── verificar-padrao.sh        # Script automatizado de checagem sintática contra o PADRAO-NOMES
├── orçamento_de_memoria_e_GPU/        # Monitoramento, dimensionamento e limites de hardware
│   ├── Orçamento de memória e GPU...pdf# Documento com a alocação teórica e limites de RAM/VRAM
│   └── tegra-teste.log                # Log amostral de telemetria coletado via tegrastats
├── política_de_armazenamento/         # Governança de disco e alertas de escassez
│   ├── alerta_disco.sh                # Script de monitoramento contínuo do uso de partições
│   └── Política de armazenamento...pdf # Diretrizes de retenção de logs e limites de partições
└── validacao/                         # Central de homologação de sistemas e aplicações na Jetson
    ├── README.md                      # Diretrizes gerais, critérios do SO e status das homologações
    ├── validacao-geral/               # Validação de infraestrutura e hardware global
    │   ├── evidencias/                # Logs e saídas da validação de hardware global
    │   └── validar-hardware.sh        # Script que checa arquitetura, GPU, CUDA, JetPack e memória
    └── a8/                            # Validação específica da aplicação A8 (modelo para novas aplicações)
        ├── README.md                  # Escopo do teste e instruções de execução da aplicação A8
        ├── RELATORIO-VALIDACAO.md     # Critérios de aceitação, testes realizados e parecer final
        ├── validar-a8-fluxo.sh        # Script automatizado do fluxo ponta a ponta da API da aplicação
        └── evidencias/                # Logs gerados pelo script com data na nomenclatura

```

---

## 🛠️ Detalhamento dos Módulos e Finalidades

### 1. Imagem Base (`image-base-v1`)
Responsável por documentar o estado exato da partição raiz gerada a partir do equipamento original `ods-pc`.

*   **Informações de Compilação:**
    *   **L4T:** R36.4.7 | **JetPack:** 6.2.1 | **CUDA:** 12.6
    *   **Arquivo de Destino:** `imagem-base-v1.tar.zst` (Compactado: ~9.1 GiB | Expandido: ~21.8 GiB)
    *   **Hash SHA-256:** `21ecc4ada2912ee077589be450707e0b5bfdbab5d36f6462f7907344d2363ea7`
*   **Exclusões de Segurança:** Por padrão, os scripts ignoram os diretórios `/home`, `/tmp`, `/var/tmp`, partições brutas de firmware de boot e imagens Docker locais ativos no momento.
*   **Verificação de Integridade:**
    ```bash
    sha256sum -c image-base-v1/imagem-base-v1.sha256
    ```

### 2. Governança e Padronização (`padronizacao`)
Garante a integridade do pipeline de auditoria através da checagem estrita de nomes de arquivos.
*   O diretório `evidencias/` armazena saídas cruas de build, testes negativos e respostas estruturadas de modelos de visão (como mapeamentos de classes em arquivos `labels-*.txt`).
*   O utilitário `verificar-padrao.sh` faz o parse dos nomes destes arquivos garantindo conformidade com a convenção descrita no manual `PADRAO-NOMES.md`.

### 3. Orçamento de Memória e GPU
Controle preciso de consumo para evitar cenários de gargalo de memória (*Out of Memory - OOM*).
*   Acompanha dados do `tegra-teste.log` coletados diretamente de registradores do SoC Tegra para validar se as janelas de processamento estão dentro das margens estipuladas no PDF técnico associado.

### 4. Política de Armazenamento
Estratégia voltada para evitar travamentos do sistema operacional causados pelo preenchimento total do disco (100% de uso na raiz).
*   O script `alerta_disco.sh` foi desenvolvido para atuar de forma ativa (podendo ser associado a uma *cron job*), disparando notificações de aviso quando limiares críticos definidos na política formal forem ultrapassados.

---

## 🚀 Como Utilizar Este Repositório

1.  **Auditar Conformidade de Logs:**
    ```bash
    cd image-base-v1/padronizacao/
    ./verificar-padrao.sh
    ```
2.  **Monitorar Partição em Produção:**
    ```bash
    cd política_de_armazenamento/
    chmod +x alerta_disco.sh
    ./alerta_disco.sh
    ```

---
*Nota: A imagem do sistema de arquivos (`imagem-base-v1.tar.zst`) não está embarcada neste repositório Git devido ao seu tamanho massivo (~9.1 GiB).*
