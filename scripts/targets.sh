#!/usr/bin/env bash
# Print the bake target names for a selection:  targets.sh [lang | lang:version]...
#   targets.sh              -> default            (everything)
#   targets.sh java         -> java               (all Java versions)
#   targets.sh java:21 go   -> java-build-21 java-runtime-21 go
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

if [ $# -eq 0 ]; then echo default; exit 0; fi
for s in "$@"; do
  case $s in
    *:*)
      selection "$s" | while read -r l v; do
        for r in $(roles "$l"); do echo "$l-$r-$(slug "$v")"; done
      done ;;
    *) selection "$s" >/dev/null; echo "$s" ;;
  esac
done
