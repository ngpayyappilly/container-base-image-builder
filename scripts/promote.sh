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
  # Keep the digest we are replacing as :<v>-previous = the rollback target (scripts/rollback.sh).
  # Skipped on the very first publish (no floating tag yet) and when nothing changes.
  current=$(docker buildx imagetools inspect "$repo:$v" --format '{{.Manifest.Digest}}' 2>/dev/null || true)
  if [[ "$current" == sha256:* && "$current" != "$digest" ]]; then
    run docker buildx imagetools create --tag "$repo:$v-previous" "$repo@$current"
  fi
  run docker buildx imagetools create --tag "$repo:$v" "$repo@$digest"
done
