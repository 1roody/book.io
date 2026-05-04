# Como Rodar as Ferramentas de Segurança Manualmente

Este guia mostra como executar cada ferramenta de segurança usada no pipeline fora do contexto do GitHub Actions, permitindo rodar scans localmente e visualizar os resultados.

---

## 1. SAST — Semgrep

**Workflow:** `.github/workflows/_sast.yml`

### Instalação

```bash
python3 -m pip install semgrep
```

### Execução (scan completo do repositório)

```bash
semgrep scan --config auto --json --output semgrep-results.json
semgrep scan --config auto --sarif --output semgrep-results.sarif
```

### Execução (scan de arquivos específicos)

```bash
semgrep scan --config auto --json --output semgrep-results.json app.py outro_arquivo.py
```

### Visualização dos resultados

```bash
semgrep scan --config auto .
cat semgrep-results.json | python3 -m json.tool | less
```

---

## 2. Secret Scan — Gitleaks

**Workflow:** `.github/workflows/_secret-scan.yml`

### Instalação

```bash
curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.30.0/gitleaks_8.30.0_linux_x64.tar.gz \
  | tar -xz -C /usr/local/bin gitleaks

gitleaks version
```

### Execução — scan do diretório (arquivos em disco)

```bash
gitleaks dir . \
  --report-format json \
  --report-path gitleaks-results.json \
  --redact \
  --verbose \
  --exit-code 0

gitleaks dir . \
  --report-format sarif \
  --report-path gitleaks-results.sarif \
  --redact \
  --verbose \
  --exit-code 0
```

### Execução — scan do histórico git (commits)

```bash
gitleaks git . \
  --report-format json \
  --report-path gitleaks-results.json \
  --redact \
  --verbose \
  --exit-code 0

gitleaks git . \
  --log-opts "abc1234..def5678" \
  --report-format json \
  --report-path gitleaks-results.json \
  --redact \
  --verbose \
  --exit-code 0
```

> **Nota:** `--exit-code 0` faz a ferramenta nunca retornar erro mesmo encontrando segredos, útil para não interromper scripts. Para uso interativo, remova essa flag.

### Visualização dos resultados

```bash
cat gitleaks-results.json | python3 -m json.tool | less
```

---

## 3. SCA (Dependências) — Trivy Filesystem Scan

**Workflow:** `.github/workflows/_dependency-scan.yml`

> Requer Docker instalado.

### Execução — scan de dependências do projeto

```bash
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  fs \
  --severity CRITICAL,HIGH,MEDIUM \
  --format json \
  --output trivy-fs-results.json \
  .

docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  fs \
  --severity CRITICAL,HIGH,MEDIUM \
  --format sarif \
  --output trivy-fs-results.sarif \
  .
```

### Visualização dos resultados

```bash
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  fs \
  --severity CRITICAL,HIGH,MEDIUM \
  .

cat trivy-fs-results.json | python3 -m json.tool | less
```

---

## 4. IaC — Trivy Config Scan

**Workflow:** `.github/workflows/_iac.yml`

> Requer Docker instalado.

### Execução — scan de arquivos de infraestrutura

```bash
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  config \
  --severity CRITICAL,HIGH \
  --format json \
  --output trivy-iac-results.json \
  ./iac-demo

docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  config \
  --severity CRITICAL,HIGH \
  --format sarif \
  --output trivy-iac-results.sarif \
  ./iac-demo
```

> Substitua `./iac-demo` por qualquer pasta que contenha arquivos `.yml`, `.yaml`, `.json`, `.tf` ou `.tfvars`.

### Visualização dos resultados

```bash
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  config \
  --severity CRITICAL,HIGH \
  ./iac-demo

cat trivy-iac-results.json | python3 -m json.tool | less
```

---

## 5. Container Scan — Trivy Image Scan

**Workflows:** `.github/workflows/_build.yml` e `_container-scan.yml`

> Requer Docker instalado e a imagem já construída localmente.

### Pré-requisito: construir a imagem local

```bash
docker build -t bookio:local .
```

### Execução — scan da imagem Docker

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  image \
  --image-src docker \
  --severity CRITICAL,HIGH,MEDIUM \
  --format sarif \
  --output trivy-results.sarif \
  bookio:local
```

> No pipeline, o alvo é a imagem publicada no GHCR (`ghcr.io/usuario/repo@sha256:...`). Localmente, use a tag da imagem construída (`bookio:local`).

### Visualização dos resultados

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.69.3 \
  image \
  --severity CRITICAL,HIGH,MEDIUM \
  bookio:local

cat trivy-results.sarif | python3 -m json.tool | less
```

---

## 6. DAST — OWASP ZAP

**Workflow:** `.github/workflows/_dast.yml`

> Requer Docker instalado e a aplicação rodando e acessível em uma URL.

### Pré-requisito: aplicação rodando localmente

```bash
docker compose up -d
docker run -p 3000:3000 bookio:local
npm start
```

### Execução — active scan em um endpoint

```bash
mkdir -p zap-output && chmod 777 zap-output

docker run --rm \
  -v "$(pwd)/zap-output:/zap/wrk/:rw" \
  -u root \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-full-scan.py \
    -t "http://localhost:3000/livros" \
    -r "zap-report-livros.html" \
    -J "zap-report-livros.json" \
    -a \
    -I
```

### Execução — múltiplos endpoints (equivalente ao pipeline)

```bash
mkdir -p zap-output && chmod 777 zap-output
APP_URL="http://localhost:3000"

declare -a TARGETS=(
  "${APP_URL}/livros"
  "${APP_URL}/segredo"
  "${APP_URL}/xss?nome=teste"
  "${APP_URL}/sql?q=teste"
)

for index in "${!TARGETS[@]}"; do
  target="${TARGETS[$index]}"
  report_prefix="zap-report-$((index + 1))"

  docker run --rm \
    -v "$(pwd)/zap-output:/zap/wrk/:rw" \
    -u root \
    ghcr.io/zaproxy/zaproxy:stable \
    zap-full-scan.py \
      -t "${target}" \
      -r "${report_prefix}.html" \
      -J "${report_prefix}.json" \
      -a \
      -I
done
```

> **Flags importantes:**
> - `-t` → URL alvo do scan
> - `-r` → relatório em HTML
> - `-J` → relatório em JSON
> - `-a` → inclui scan ativo (não só passivo)
> - `-I` → não falha mesmo se encontrar alertas (útil para não interromper o script)

### Visualização dos resultados

```bash
xdg-open zap-output/zap-report-1.html   # Linux
open zap-output/zap-report-1.html       # macOS

cat zap-output/zap-report-1.json | python3 -m json.tool | less
```

---

## Resumo das ferramentas

| Ferramenta | Tipo | Workflow | Requer Docker |
|---|---|---|---|
| Semgrep | SAST | `_sast.yml` | Não |
| Gitleaks | Secret Scan | `_secret-scan.yml` | Não |
| Trivy FS | SCA / Dependências | `_dependency-scan.yml` | Sim |
| Trivy Config | IaC | `_iac.yml` | Sim |
| Trivy Image | Container Scan | `_build.yml` + `_container-scan.yml` | Sim |
| OWASP ZAP | DAST | `_dast.yml` | Sim |
