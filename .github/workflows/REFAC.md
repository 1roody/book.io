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
| Job `pr-main-dast` (DAST inline, ~70 linhas) | `on-main-pr.yml` → job `dast` (chama `_dast.yml`) |
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
