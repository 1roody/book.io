# Como Rodar as Ferramentas de Segurança Manualmente

Este guia mostra como executar cada ferramenta de segurança usada no pipeline fora do contexto do GitHub Actions, permitindo rodar scans localmente e visualizar os resultados.

---

## 1. SAST — Semgrep

**Workflow:** `.github/workflows/sast.yml`

### Instalação

```bash
python3 -m pip install semgrep
```

### Execução (scan completo do repositório)

```bash
# Gera resultado em JSON
semgrep scan --config auto --json --output semgrep-results.json

# Gera resultado em SARIF (compatível com GitHub Code Scanning)
semgrep scan --config auto --sarif --output semgrep-results.sarif
```

### Execução (scan de arquivos específicos)

```bash
semgrep scan --config auto --json --output semgrep-results.json app.py outro_arquivo.py
```

### Visualização dos resultados

```bash
# Ver todos os findings no terminal (sem salvar arquivo)
semgrep scan --config auto .

# Ver o JSON formatado
cat semgrep-results.json | python3 -m json.tool | less

# Resumo rápido: contar findings por severidade
cat semgrep-results.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('results', [])
for r in results:
    print(r['check_id'], '-', r['path'], 'linha', r['start']['line'])
"
```

---

## 2. Secret Scan — Gitleaks

**Workflow:** `.github/workflows/secret-scan.yml`

### Instalação

```bash
curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.30.0/gitleaks_8.30.0_linux_x64.tar.gz \
  | tar -xz -C /usr/local/bin gitleaks

# Verificar versão
gitleaks version
```

### Execução — scan do diretório (arquivos em disco)

```bash
# Gera resultado em JSON
gitleaks dir . \
  --report-format json \
  --report-path gitleaks-results.json \
  --redact \
  --verbose \
  --exit-code 0

# Gera resultado em SARIF
gitleaks dir . \
  --report-format sarif \
  --report-path gitleaks-results.sarif \
  --redact \
  --verbose \
  --exit-code 0
```

### Execução — scan do histórico git (commits)

```bash
# Scan de todo o histórico
gitleaks git . \
  --report-format json \
  --report-path gitleaks-results.json \
  --redact \
  --verbose \
  --exit-code 0

# Scan de um intervalo de commits específico
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
# Ver o JSON formatado
cat gitleaks-results.json | python3 -m json.tool | less

# Listar descrição e arquivo de cada finding
cat gitleaks-results.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data:
    print(item.get('Description'), '|', item.get('File'), '| linha', item.get('StartLine'))
"
```

---

## 3. SCA (Dependências) — Trivy Filesystem Scan

**Workflow:** `.github/workflows/dependency-scan.yml`

> Requer Docker instalado.

### Execução — scan de dependências do projeto

```bash
# Gera resultado em JSON
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  fs \
  --severity CRITICAL,HIGH,MEDIUM \
  --format json \
  --output trivy-fs-results.json \
  .

# Gera resultado em SARIF
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
# Ver no terminal diretamente (sem salvar arquivo)
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  fs \
  --severity CRITICAL,HIGH,MEDIUM \
  .

# Ver o JSON formatado
cat trivy-fs-results.json | python3 -m json.tool | less

# Listar vulnerabilidades encontradas
cat trivy-fs-results.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for result in data.get('Results', []):
    target = result.get('Target', '')
    for vuln in result.get('Vulnerabilities', []):
        print(vuln['Severity'], '|', vuln['VulnerabilityID'], '|', vuln['PkgName'], '|', target)
"
```

---

## 4. IaC — Trivy Config Scan

**Workflow:** `.github/workflows/iac.yml`

> Requer Docker instalado.

### Execução — scan de arquivos de infraestrutura

```bash
# Gera resultado em JSON (pasta iac-demo é o alvo padrão do projeto)
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  config \
  --severity CRITICAL,HIGH \
  --format json \
  --output trivy-iac-results.json \
  ./iac-demo

# Gera resultado em SARIF
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
# Ver no terminal diretamente
docker run --rm \
  -v "$(pwd):/work" \
  -w /work \
  aquasec/trivy:0.69.3 \
  config \
  --severity CRITICAL,HIGH \
  ./iac-demo

# Ver o JSON formatado
cat trivy-iac-results.json | python3 -m json.tool | less

# Listar misconfigurations encontradas
cat trivy-iac-results.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for result in data.get('Results', []):
    target = result.get('Target', '')
    for m in result.get('Misconfigurations', []):
        print(m['Severity'], '|', m['ID'], '|', m['Title'], '|', target)
"
```

---

## 5. Container Scan — Trivy Image Scan

**Workflow:** `.github/workflows/build-and-container-scan.yml`

> Requer Docker instalado e a imagem já construída localmente.

### Pré-requisito: construir a imagem local

```bash
docker build -t bookio:local .
```

### Execução — scan da imagem Docker

```bash
# Gera resultado em SARIF
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
# Ver no terminal diretamente
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.69.3 \
  image \
  --severity CRITICAL,HIGH,MEDIUM \
  bookio:local

# Ver o SARIF formatado
cat trivy-results.sarif | python3 -m json.tool | less
```

---

## 6. DAST — OWASP ZAP

**Workflow:** `.github/workflows/dast-and-deploy.yml`

> Requer Docker instalado e a aplicação rodando e acessível em uma URL.

### Pré-requisito: aplicação rodando localmente

```bash
# Exemplo: subir a aplicação com Docker
docker run -p 5000:5000 bookio:local

# Ou diretamente com Python
python3 app.py
```

### Execução — active scan em um endpoint

```bash
# Preparar pasta de saída com permissão de escrita para o container ZAP
mkdir -p zap-output && chmod 777 zap-output

# Scan ativo em um endpoint (substitua a URL pelo endereço da sua aplicação)
docker run --rm \
  -v "$(pwd)/zap-output:/zap/wrk/:rw" \
  -u root \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-full-scan.py \
    -t "http://localhost:5000/livros" \
    -r "zap-report-livros.html" \
    -J "zap-report-livros.json" \
    -a \
    -I
```

### Execução — múltiplos endpoints (equivalente ao pipeline)

```bash
mkdir -p zap-output && chmod 777 zap-output
APP_URL="http://localhost:5000"

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
# Abrir o relatório HTML no navegador
xdg-open zap-output/zap-report-1.html   # Linux
open zap-output/zap-report-1.html       # macOS

# Ver o JSON formatado
cat zap-output/zap-report-1.json | python3 -m json.tool | less

# Listar alertas encontrados
cat zap-output/zap-report-1.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for site in data.get('site', []):
    for alert in site.get('alerts', []):
        print(alert['riskdesc'], '|', alert['name'], '|', alert['instances'][0]['uri'])
"
```

---

## Resumo das ferramentas

| Ferramenta | Tipo | Workflow | Requer Docker |
|---|---|---|---|
| Semgrep | SAST | `sast.yml` | Não |
| Gitleaks | Secret Scan | `secret-scan.yml` | Não |
| Trivy FS | SCA / Dependências | `dependency-scan.yml` | Sim |
| Trivy Config | IaC | `iac.yml` | Sim |
| Trivy Image | Container Scan | `build-and-container-scan.yml` | Sim |
| OWASP ZAP | DAST | `dast-and-deploy.yml` | Sim |
