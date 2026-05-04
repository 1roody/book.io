# book.io

API REST de CRUD de livros com vulnerabilidades intencionais, projetada para demonstrar ferramentas de segurança ao longo do ciclo de desenvolvimento (SAST, DAST, SCA, IaC, secret scan e container scan) em um pipeline GitHub Actions completo.

---

## Sobre o projeto

**book.io** é uma aplicação Node.js/Express que expõe endpoints deliberadamente inseguros para servir como alvo de scanners de segurança. O objetivo é educacional: mostrar como cada categoria de vulnerabilidade é detectada por ferramentas específicas integradas em um pipeline de CI/CD.

| Camada | Ferramenta | O que detecta |
|---|---|---|
| SAST | Semgrep | Vulnerabilidades no código-fonte |
| Secret Scan | Gitleaks | Credenciais hardcoded no código/histórico git |
| SCA | Trivy FS | Dependências npm com CVEs conhecidos |
| IaC | Trivy Config | Misconfigurations em manifests Kubernetes |
| Container Scan | Trivy Image | CVEs na imagem Docker |
| DAST | OWASP ZAP | Vulnerabilidades em runtime (XSS, SQLi, redirect) |

---

## Endpoints

| Método | Rota | Descrição | Vulnerabilidade |
|---|---|---|---|
| GET | `/health` | Health check | — |
| GET | `/livros` | Lista todos os livros | — |
| GET | `/livros/:id` | Retorna um livro por ID | — |
| POST | `/livros` | Cria um livro | — |
| PUT | `/livros/:id` | Atualiza um livro | — |
| DELETE | `/livros/:id` | Remove um livro | — |
| GET | `/segredo` | Expõe variável de ambiente | Exposição de segredo |
| GET | `/xss?nome=` | Reflete parâmetro sem sanitização | XSS refletido |
| GET | `/sql?q=` | Executa query sem parameterização | SQL Injection |
| GET | `/redirect?url=` | Redireciona para URL arbitrária | Open Redirect |

---

## Pré-requisitos

- [Node.js](https://nodejs.org/) 20+ (ou [Devbox](https://www.jetify.com/devbox) — recomendado)
- [Docker](https://www.docker.com/) (necessário para Trivy, ZAP e build da imagem)

---

## Como rodar localmente

### Com Devbox (recomendado)

Devbox garante paridade de versões entre o ambiente local e o CI.

```bash
# Instalar Devbox (apenas uma vez)
curl -fsSL https://get.jetify.com/devbox | bash

# Entrar no ambiente isolado com as ferramentas fixadas
devbox install
devbox shell
```

Dentro do shell do Devbox:

```bash
devbox run install   # npm ci
devbox run dev       # inicia o servidor na porta 3000
```

### Com Node.js diretamente

```bash
npm install
cp .env.example .env   # ajuste as variáveis se necessário
npm start              # porta 3000
```

### Com Docker Compose

```bash
docker compose up -d
```

A aplicação estará disponível em `http://localhost:3000`.

---

## Como rodar os scanners de segurança

Consulte [docs/how_to_run.md](docs/how_to_run.md) para comandos completos de cada ferramenta.

Com Devbox, os atalhos abaixo executam os mesmos scanners que rodam no CI:

```bash
devbox run test:secrets   # Gitleaks — secret scan no diretório
devbox run test:sast      # Semgrep — análise estática
devbox run test:deps      # Trivy FS — dependências
devbox run test:iac       # Trivy Config — manifests em iac-demo/
devbox run build:image    # build local da imagem (necessário para container scan)
```

---

## Pipeline de CI/CD

O pipeline é composto por **13 workflows** em `.github/workflows/`, divididos em orquestradores (prefixo `on-`) e reusables (prefixo `_`):

```
Push em feature/**
  └─ on-feature-push.yml → secret-scan + dependency-scan

PR para develop
  └─ on-develop-pr.yml → SAST + secret-scan + dependency-scan + IaC

PR develop → main
  └─ on-main-pr.yml → build + container-scan + DAST (imagem local)

Push em main
  └─ on-main-push.yml
       ├─ Stage 1: build + container-scan → publica no GHCR
       └─ Stage 2: deploy no Render + DAST (URL pública)

Semanal (domingo 04:00 UTC)
  └─ on-cron-prune.yml → limpeza de imagens antigas no GHCR
```

Todos os resultados de scan são enviados ao **GitHub Code Scanning** como SARIF e arquivados como artifacts por 30 dias.

---

## Estrutura do projeto

```
book.io/
├── .github/
│   ├── workflows/        # 13 workflows (5 orquestradores + 8 reusables)
│   └── actions/          # 3 composite actions (trivy-scan, upload-results, resolve-targets)
├── src/
│   └── index.js          # Servidor Express + endpoints vulneráveis
├── iac-demo/
│   └── k8s/
│       └── insecure-pod.yaml  # Manifest K8s intencionalmente inseguro (alvo do Trivy Config)
├── scripts/
│   ├── prune-ghcr.sh     # Limpeza de versões antigas no GHCR
│   └── zap.sh            # Helper para ZAP local
├── docs/
│   └── how_to_run.md     # Como rodar cada scanner manualmente
├── Dockerfile            # Imagem node:14 (EOL intencional — gera CVEs para demonstração)
├── docker-compose.yml    # Stack local
├── devbox.json           # Ambiente de desenvolvimento com versões fixadas
└── .env.example          # Variáveis de ambiente de exemplo
```

---

## Variáveis de ambiente

| Variável | Descrição | Padrão |
|---|---|---|
| `PORT` | Porta do servidor | `3000` |
| `SEGREDO_SUPERSECRETO` | Valor exposto em `/segredo` (intencional) | `valor-muito-secreto` |

---

## Registro de container

A imagem é publicada no GitHub Container Registry (GHCR) a cada push em `main`:

```
ghcr.io/1roody/bookio:latest
```

Versões antigas são removidas automaticamente toda semana, mantendo sempre a tag `latest` e as 3 versões mais recentes.
