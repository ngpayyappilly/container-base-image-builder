#!/usr/bin/env bash
# Pull the release candidates that `bake --push --metadata-file` just published (by DIGEST,
# i.e. the exact bytes that will be promoted) and tag them locally as local/<image>:<version>,
# so verify.sh / smoke-test.sh / scan.sh (REGISTRY=local) test what ships.
# Usage: GIT_SHA=<12 chars> scripts/pull-candidates.sh meta.json
set -euo pipefail
meta=${1:?usage: pull-candidates.sh meta.json}
: "${GIT_SHA:?GIT_SHA must match the one used for the build}"
run() { if [[ -n "${DRY_RUN:-}" ]]; then echo "+ $*"; else "$@"; fi; }

jq -r 'to_entries[] | "\(.value["image.name"] | split(",")[0])\t\(.value["containerimage.digest"])"' "$meta" |
while IFS=$'\t' read -r name digest; do
  repo=${name%:*}; tag=${name##*:}   # ghcr.io/o/go-build : 1.27-<sha>
  img=${repo##*/}; v=${tag%-"$GIT_SHA"}
  run docker pull --quiet "$repo@$digest"
  run docker tag "$repo@$digest" "local/$img:$v"
done
