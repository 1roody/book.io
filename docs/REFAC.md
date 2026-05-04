# Refatoração dos Workflows do GitHub Actions

Este documento registra a reorganização dos arquivos em `.github/workflows/`.
**Nenhum trigger, ordem de execução ou comportamento de scan foi alterado** — apenas a estrutura de arquivos e nomes.

---

## 1. Motivação

Antes da refatoração existiam 7 arquivos com problemas de coesão:

- `pipeline.yml` (orquestrador) misturava 4 cenários distintos (push em feature, PR para develop, PR para main, push em main) em um único arquivo de ~220 linhas, com `if`s complexos para distinguir cada caso.
- A lógica de **DAST estava duplicada**: existia inline dentro de `pipeline.yml` (job `pr-main-dast`) e também dentro de `dast-and-deploy.yml` — duas implementações de ZAP para manter.
- Arquivos com nomes "X-and-Y" (`build-and-container-scan.yml`, `dast-and-deploy.yml`) misturavam responsabilidades, ao contrário dos demais reusables (`sast.yml`, `iac.yml`, etc.) que eram single-purpose.
- Não havia distinção visual entre **orquestradores** (acionados por evento) e **reusables** (chamados por outros workflows).

---

## 2. Nova estrutura

```
.github/workflows/
├── on-feature-push.yml       # trigger: push em feature/**
├── on-develop-pr.yml         # trigger: PR -> develop
├── on-main-pr.yml            # trigger: PR develop -> main
├── on-main-push.yml          # trigger: push em main
│
├── _build.yml                # reusable: build da imagem Docker
├── _container-scan.yml       # reusable: Trivy image scan
├── _deploy.yml               # reusable: trigger do deploy no Render
├── _dast.yml                 # reusable: OWASP ZAP (unificado)
├── _sast.yml                 # reusable: Semgrep
├── _secret-scan.yml          # reusable: Gitleaks
├── _dependency-scan.yml      # reusable: Trivy filesystem
└── _iac.yml                  # reusable: Trivy config
```

### Convenção de nomes

- **`on-*.yml`** → orquestradores. Cada um responde a **um único tipo de evento** e tem o `trigger` declarado dentro dele.
- **`_*.yml`** (com underscore) → reusables (`workflow_call`). O underscore é uma convenção visual para indicar que **não são acionados diretamente** por eventos, e sim chamados por outros workflows. Alfabeticamente eles ficam agrupados separadamente dos orquestradores.

---

## 3. Mapeamento antigo → novo

### Orquestrador

| Antes (`pipeline.yml`) | Agora |
|---|---|
| Job `feature-secret-scan` (com `if` de push em feature/**) | `on-feature-push.yml` → job `secret-scan` |
| Job `feature-dependency-scan` | `on-feature-push.yml` → job `dependency-scan` |
| Job `develop-sast` | `on-develop-pr.yml` → job `sast` |
| Job `develop-secret-scan` | `on-develop-pr.yml` → job `secret-scan` |
| Job `develop-dependency-scan` | `on-develop-pr.yml` → job `dependency-scan` |
| Job `develop-iac` | `on-develop-pr.yml` → job `iac` |
| Job `pr-main-build-and-container-scan` | `on-main-pr.yml` → jobs `build` + `container-scan` |
| Job `main-build` | `on-main-push.yml` → jobs `stage-1-build` + `stage-1-container-scan` |
| Job `main-deploy` | `on-main-push.yml` → jobs `stage-2-deploy` + `stage-2-dast` |

### Reusables

| Antes | Agora | Mudança |
|---|---|---|
| `sast.yml` | `_sast.yml` | apenas renomeado |
| `secret-scan.yml` | `_secret-scan.yml` | apenas renomeado |
| `dependency-scan.yml` | `_dependency-scan.yml` | apenas renomeado |
| `iac.yml` | `_iac.yml` | apenas renomeado |
| `build-and-container-scan.yml` (2 jobs) | `_build.yml` + `_container-scan.yml` | dividido em 2 arquivos single-purpose |
| `dast-and-deploy.yml` (2 jobs) | `_deploy.yml` + `_dast.yml` | dividido em 2 arquivos single-purpose |
| DAST inline em `pipeline.yml` (job `pr-main-dast`) | `_dast.yml` | unificado com a versão do `dast-and-deploy.yml` |

---

## 4. Novidades

### `_dast.yml` unificado

Antes existiam **duas** implementações de DAST:
- A do `pipeline.yml` (inline) buildava uma imagem local, subia container na porta 3000 e rodava ZAP via `docker run`.
- A do `dast-and-deploy.yml` rodava ZAP usando a action oficial `zaproxy/action-full-scan` contra uma URL deployada.

Agora há **uma única** implementação em `_dast.yml`, controlada por dois inputs:
- `target_url` (obrigatório): URL base a ser escaneada.
- `build_local_image` (opcional, default `false`): se `true`, builda o Dockerfile e sobe um container local antes de escanear (caso PR para main); se `false`, escaneia diretamente a URL externa (caso push em main → URL do Render).

Ambas usam a action oficial `zaproxy/action-full-scan@v0.12.0` com matriz de 4 endpoints (`livros`, `segredo`, `xss`, `sql`).

### Stage 1 / Stage 2 no push em main

No `on-main-push.yml`, os jobs receberam `name: Stage 1` ou `name: Stage 2` para que a UI do Actions exiba:

```
Stage 1 / Build              ← _build.yml
Stage 1 / Container Scan     ← _container-scan.yml
Stage 2 / Deploy             ← _deploy.yml
Stage 2 / OWASP ZAP (...)    ← _dast.yml (matriz)
```

Antes, no flow do main push, o Container Scan aparecia como **skipped (0s)** porque o reusable `build-and-container-scan.yml` recebia a flag `run_container_scan: false`. Agora, como cada reusable é single-purpose, **o orquestrador é quem decide se chama ou não** — e no main push ele chama os dois.

### Eliminação de flags condicionais

Como cada reusable agora faz uma única coisa, sumiram do código:
- `run_container_scan` (flag em `build-and-container-scan.yml`)
- `run_dast` (flag em `dast-and-deploy.yml`)

A decisão de "rodar ou não" agora é simplesmente "incluir o job no orquestrador ou não".

---

## 5. O que NÃO mudou

- **Triggers**: os mesmos eventos do GitHub disparam os mesmos cenários.
  - Push em `feature/**` → secret-scan + dependency-scan
  - PR para `develop` → SAST + secret-scan + dependency-scan + IaC
  - PR `develop → main` → build + container-scan + DAST
  - Push em `main` → build + container-scan + deploy + DAST
- **Ordem e dependências entre jobs**: idênticas.
- **Permissões e secrets**: copiados sem alteração.
- **Conteúdo dos steps**: as ferramentas (Semgrep, Gitleaks, Trivy, ZAP), versões e flags são exatamente as mesmas.
- **Output `image_ref`** do build continua disponível para o deploy/scan consumirem.

---

## 6. Ações pós-merge necessárias

- **Branch protection rules** no GitHub: se houver regras exigindo status checks com nomes de jobs antigos (ex.: `pipeline / main-build`), atualizar para os novos nomes (ex.: `Main Push / Stage 1`). Verificar em *Settings → Branches → Branch protection rules*.
- **Comunicar a equipe**: a página *Actions* do GitHub agora terá 4 workflows separados em vez de 1, o que melhora a navegação mas é uma mudança visual relevante.

---

## 7. Resumo numérico

| Métrica | Antes | Depois |
|---|---|---|
| Total de arquivos | 7 | 12 |
| Arquivos > 200 linhas | 1 (`pipeline.yml`) | 0 |
| Implementações de DAST | 2 | 1 |
| Reusables single-purpose | 4 | 8 |
| `if`s condicionais por cenário em orquestrador | ~10 | 0 (cada cenário tem seu arquivo) |

---

# Rodada 2 — Padrões DevOps Directive (modularidade, cache, segurança)

Esta segunda rodada aplica práticas alinhadas ao curso DevOps Directive, mantendo o mesmo plano de execução.

## 8. Devbox para padronização de ambiente local

Adicionado [`devbox.json`](../../devbox.json) na raiz do projeto fixando versões de:
- `nodejs@20.18.1`
- `trivy@0.69.3` (mesma versão usada nos workflows)
- `gitleaks@8.30.0` (idem)
- `semgrep@1.89.0`
- `gh@2.62.0`, `jq@1.7.1`

**Como usar (alunos):**
```bash
curl -fsSL https://get.jetify.com/devbox | bash   # instala devbox
devbox install                                     # gera devbox.lock
devbox shell                                       # entra no ambiente isolado
```

**Scripts disponíveis dentro do shell:**
- `devbox run install` → `npm ci`
- `devbox run dev`     → `node index.js`
- `devbox run test:secrets|test:sast|test:deps|test:iac` → mesmas ferramentas que rodam no CI
- `devbox run build:image` → build local da imagem

**Importante**: o `devbox.lock` é gerado por `devbox install` e deve ser commitado no repo (faz o papel de lockfile, fixando hashes Nix). Cada aluno deve gerar localmente na primeira vez.

## 9. Composite Actions para abstração

Lógica duplicada extraída para reutilização em [`.github/actions/`](../actions/):

| Composite | Substitui | Usado em |
|---|---|---|
| `resolve-changed-targets` | Bloco de ~25 linhas de bash que aparecia em 3 reusables | `_sast.yml`, `_dependency-scan.yml`, `_iac.yml` |
| `trivy-scan` | Comandos `docker run aquasec/trivy` repetidos | `_dependency-scan.yml`, `_iac.yml`, `_container-scan.yml` |
| `upload-security-results` | Bloco SARIF + artifact upload duplicado em todos | Todos os reusables de scan |

**Ganho**: o reusable `_iac.yml` saiu de 111 → ~50 linhas. Mudanças em "como subimos SARIF" passam a ser feitas em **um lugar**.

## 10. Caching inteligente

Adicionado em vários níveis:

| Cache | Local | Hit típico |
|---|---|---|
| Trivy DB de vulnerabilidades | `~/.cache/trivy` (composite `trivy-scan`) | Reduz download de ~50MB por job |
| Buildx layers (GHA backend) | `cache-from: type=gha` em `_build.yml` e `_container-scan.yml` | Skip de camadas Docker inalteradas |
| Semgrep rules | `~/.semgrep` em `_sast.yml` | Evita re-download de regras `auto` |
| Binário do Gitleaks | `/usr/local/bin/gitleaks` em `_secret-scan.yml` | Pula `curl + tar` se já cacheado |

A chave do cache do Trivy DB usa `${{ github.run_id }}` para forçar update por execução, com `restore-keys` para fallback — padrão recomendado pela própria docs do Trivy.

## 11. Least-privilege nas permissions

Aplicado o padrão **"deny-by-default + grant-per-job"**:

- Todos os orquestradores (`on-*.yml`) declaram `permissions: {}` no nível do workflow → **revoga** o token padrão.
- Cada job declara só as permissions de que precisa.
- **Removidas** permissões desnecessárias dos triggers de push (não há contexto de PR):
  - `pull-requests: read` ❌ (irrelevante em push)
  - `actions: read` ❌ (não usamos a API de actions)
- **Downgrade** em `_deploy.yml` na orquestração: `packages: write` → `packages: read` (deploy só lê o registry, não publica).

## 12. Limpeza automática de imagens GHCR

[`scripts/prune-ghcr.sh`](../../scripts/prune-ghcr.sh) remove versões antigas mantendo:
- Sempre a tag `latest`.
- As 3 versões mais recentes (configurável via `KEEP_COUNT`).

[`on-cron-prune.yml`](on-cron-prune.yml) executa o script semanalmente (domingo, 04:00 UTC) e oferece `workflow_dispatch` com flag `dry_run` para auditar sem deletar.

**Teste manual:**
```bash
GH_OWNER=1roody GH_PACKAGE=bookio DRY_RUN=true ./scripts/prune-ghcr.sh
```

## 13. O que **não** foi aplicado e por quê

| Diretriz | Status | Motivo |
|---|---|---|
| Taskfile (`go-task`) | ❌ pulado | Redundante com `npm scripts` num projeto Node puro. Reavaliar quando entrar IaC/multi-linguagem. |
| `act` para validação local | ❌ pulado | Suporte limitado a `workflow_call` cross-file, matrices e GHCR login. Devbox cobre o uso real (rodar as mesmas ferramentas localmente). |
| GitOps (ArgoCD/Flux) | ❌ pulado | Deploy é em Render via webhook — não há cluster K8s nem agente reconciliador. Aplicar GitOps aqui seria cargo cult. Caberia em projeto separado com Kind + ArgoCD. |

## 14. Resumo da rodada 2

- **3 composite actions** novas em `.github/actions/`
- **6 caches** adicionados (Trivy DB, Buildx, Semgrep, Gitleaks)
- **`permissions: {}`** em todos os 5 orquestradores (deny-by-default)
- **1 script** de manutenção + **1 workflow agendado** para limpeza GHCR
- **Devbox** para paridade ambiente local ↔ CI

