#!/usr/bin/env bash
set -euo pipefail

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
    --network=host \
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