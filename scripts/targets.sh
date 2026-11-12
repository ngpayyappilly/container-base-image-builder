#!/usr/bin/env bash
# Print the bake target names for a selection:  targets.sh [lang | lang:version]...
#   targets.sh              -> default            (everything)
#   targets.sh java         -> java               (all Java versions)
#   targets.sh java:21 go   -> java-build-21 java-runtime-21 go
#   targets.sh tomcat:9.0-java21 -> tomcat-runtime-9-0-java21 java-build-21
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

if [ $# -eq 0 ]; then echo default; exit 0; fi
# explicit target names for one "lang version" pair. tomcat also needs java-build:<java>,
# which the example Dockerfile builds its WAR with.
expand() { # lang version
  local r
  for r in $(roles "$1"); do echo "$1-$r-$(slug "$2")"; done
  if [ "$1" = tomcat ]; then echo "java-build-$(slug "${2##*-java}")"; fi
}

for s in "$@"; do
  case $s in
    *:*|tomcat)
      selection "$s" | while read -r l v; do expand "$l" "$v"; done ;;
    *) selection "$s" >/dev/null; echo "$s" ;;
  esac
done
