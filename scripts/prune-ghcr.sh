#!/usr/bin/env bash
# Mantém apenas as 3 versões mais recentes de uma imagem GHCR + a tag "latest".
# Requer: gh CLI autenticado (com escopos: read:packages, delete:packages).
#
# Uso:
#   GH_OWNER=meu-user GH_PACKAGE=bookio ./scripts/prune-ghcr.sh
#
# Variáveis:
#   GH_OWNER       (obrigatório) Owner/org do package no GHCR
#   GH_PACKAGE     (obrigatório) Nome do container package
#   KEEP_COUNT     (opcional, default 3) Quantas versões além de "latest" manter
#   DRY_RUN        (opcional, default "false") Se "true", apenas lista o que removeria

set -euo pipefail

: "${GH_OWNER:?GH_OWNER é obrigatório}"
: "${GH_PACKAGE:?GH_PACKAGE é obrigatório}"
KEEP_COUNT="${KEEP_COUNT:-3}"
DRY_RUN="${DRY_RUN:-false}"

# Detecta se é organização ou usuário pra montar o endpoint correto
if gh api "orgs/${GH_OWNER}" --silent 2>/dev/null; then
  BASE_PATH="orgs/${GH_OWNER}"
else
  BASE_PATH="users/${GH_OWNER}"
fi

VERSIONS_API="${BASE_PATH}/packages/container/${GH_PACKAGE}/versions"

echo "==> Listando versões de ghcr.io/${GH_OWNER}/${GH_PACKAGE}"

# Lista todas as versões (paginadas), ordenadas por created_at desc (default da API)
all_versions=$(gh api --paginate "${VERSIONS_API}")

# Separa: versões que têm "latest" entre as tags vão sempre ser mantidas.
# Das demais, mantém as KEEP_COUNT mais recentes; o resto é candidato a deletar.

to_delete=$(echo "$all_versions" | jq -r --argjson keep "$KEEP_COUNT" '
  map(select(.metadata.container.tags | index("latest") | not))
  | sort_by(.created_at) | reverse
  | .[$keep:]
  | .[]
  | "\(.id)\t\((.metadata.container.tags // []) | join(","))\t\(.created_at)"
')

if [ -z "$to_delete" ]; then
  echo "==> Nada a remover. Mantendo \"latest\" + ${KEEP_COUNT} versões mais recentes."
  exit 0
fi

echo "==> Versões a remover:"
echo "$to_delete" | column -t -s $'\t' -N "ID,TAGS,CREATED_AT"

if [ "$DRY_RUN" = "true" ]; then
  echo "==> DRY_RUN=true — nada foi removido."
  exit 0
fi

while IFS=$'\t' read -r id tags created; do
  [ -z "$id" ] && continue
  echo "==> Removendo versão ${id} (tags: ${tags:-<sem tag>})"
  gh api -X DELETE "${VERSIONS_API}/${id}"
done <<< "$to_delete"

echo "==> Limpeza concluída."
