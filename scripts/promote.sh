#!/usr/bin/env bash
# Promote tested release candidates: point the floating :<version> tag at the SAME digest
# that was built, tested and signed. No rebuild, so what consumers get is what CI verified.
# Usage: GIT_SHA=<12 chars> scripts/promote.sh meta.json
set -euo pipefail
meta=${1:?usage: promote.sh meta.json}
: "${GIT_SHA:?GIT_SHA must match the one used for the build}"
run() { if [[ -n "${DRY_RUN:-}" ]]; then echo "+ $*"; else "$@"; fi; }

jq -r 'to_entries[] | "\(.value["image.name"] | split(",")[0])\t\(.value["containerimage.digest"])"' "$meta" |
while IFS=$'\t' read -r name digest; do
  repo=${name%:*}; tag=${name##*:}
  v=${tag%-"$GIT_SHA"}
  echo "promote $repo:$v -> $digest"
  run docker buildx imagetools create --tag "$repo:$v" "$repo@$digest"
done
