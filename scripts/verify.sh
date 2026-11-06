#!/usr/bin/env bash
# Assert the hardening + version invariants on locally built base images.
# Usage: REGISTRY=local scripts/verify.sh [lang | lang:version]...     (default: everything)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

REGISTRY=${REGISTRY:-local}
fail=0

ok()  { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=1; }
check() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }

# first output line of a command run inside an image
out() { docker run --rm "$@" 2>&1 | head -1; }

common_checks() { # lang version
  local l=$1 v=$2 r ref user lbl
  for r in $(roles "$l"); do
    ref="$REGISTRY/$l-$r:$v"
    user=$(docker inspect -f '{{.Config.User}}' "$ref")
    [[ "$user" == "65532:65532" ]] && ok "$l-$r USER is numeric 65532:65532" || bad "$l-$r USER is '$user'"
    if [[ "$r" == runtime* ]]; then
      for lbl in source revision created version; do
        val=$(docker inspect -f "{{index .Config.Labels \"org.opencontainers.image.$lbl\"}}" "$ref")
        if [[ -n "$val" && "$val" != unknown ]]; then :; else bad "$l-$r label $lbl missing"; fi
      done
      [[ "$(docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$ref")" == "$v" ]] \
        && ok "$l-$r version label = $v" || bad "$l-$r version label != $v"
    fi
  done
}

verify_go() { local v=$1
  local b="$REGISTRY/go-build:$v"
  [[ "$(out --entrypoint go "$b" version)" == *"go$v"* ]] && ok "go-build contains Go $v" || bad "go-build is not Go $v"
  check "go-build: GOTOOLCHAIN=local" bash -c "[[ \$(docker run --rm --entrypoint go $b env GOTOOLCHAIN) == local ]]"
  check "go-runtime has no /bin/sh"   bash -c "! docker run --rm --entrypoint /bin/sh $REGISTRY/go-runtime:$v -c true"
}

verify_java() { local v=$1
  local r="$REGISTRY/java-runtime:$v"
  # (full output, not line 1: the JVM first prints "Picked up JAVA_TOOL_OPTIONS")
  [[ "$(docker run --rm --entrypoint java "$r" -version 2>&1)" == *"version \"$v."* ]] \
    && ok "java-runtime is JDK $v" || bad "java-runtime is not JDK $v"
  check "trust store has >100 CA certs" bash -c "[[ \$(docker run --rm --entrypoint keytool $r -list -cacerts -storepass changeit | grep -c trustedCertEntry) -gt 100 ]]"
  check "CDS archive present (fast start)" docker run --rm --entrypoint java "$r" -Xshare:on -version
  check "TLS EC crypto available (jdk.crypto.ec / java.base)" bash -c "docker run --rm --entrypoint java $r --list-modules >/dev/null && docker run --rm --entrypoint java $r -XshowSettings:security:providers -version 2>&1 | grep -q SunEC"
  check "java-runtime has no /bin/sh" bash -c "! docker run --rm --entrypoint /bin/sh $r -c true"
}

verify_python() { local v=$1
  local r="$REGISTRY/python-runtime:$v"
  run_py() { docker run --rm --entrypoint python3 "$r" -c "$1"; }
  [[ "$(out --entrypoint python3 "$r" --version)" == "Python $v."* ]] && ok "python-runtime is Python $v" || bad "python-runtime is not Python $v"
  check "no setuid/setgid files" run_py 'import os,stat,sys
bad=[os.path.join(d,f) for d,_,fs in os.walk("/") if not d.startswith(("/proc","/sys","/dev")) for f in fs
     if os.path.isfile(os.path.join(d,f)) and not os.path.islink(os.path.join(d,f))
     and os.stat(os.path.join(d,f)).st_mode & (stat.S_ISUID|stat.S_ISGID)]
print(bad); sys.exit(1 if bad else 0)'
  check "interpreter starts cleanly (no stderr noise)" bash -c "[[ -z \$(docker run --rm --entrypoint python3 $r -c pass 2>&1) ]]"
  check "pip is gone"                   run_py 'import importlib.util,sys; sys.exit(1 if importlib.util.find_spec("pip") else 0)'
  check "apt/dpkg binaries are gone"    run_py 'import os,sys; sys.exit(1 if any(os.path.exists(p) for p in ["/usr/bin/apt","/usr/bin/apt-get","/usr/bin/dpkg"]) else 0)'
  check "dpkg status kept for scanners" run_py 'import os,sys; sys.exit(0 if os.path.getsize("/var/lib/dpkg/status")>0 else 1)'
  check "root login shell is nologin"   run_py 'import pwd,sys; sys.exit(0 if pwd.getpwnam("root").pw_shell.endswith("nologin") else 1)'
  check "runs as uid 65532"             run_py 'import os,sys; sys.exit(0 if os.getuid()==65532 else 1)'
  check "tini is the entrypoint"        bash -c "docker inspect -f '{{json .Config.Entrypoint}}' $r | grep -q tini"
  [[ "$(out "$REGISTRY/python-build:$v" python --version)" == "Python $v."* ]] && ok "python-build is Python $v" || bad "python-build is not Python $v"
}

verify_node() { local v=$1
  local r="$REGISTRY/node-runtime:$v"
  [[ "$(out "$r" -p process.version)" == "v$v."* ]] && ok "node-runtime is Node $v" || bad "node-runtime is not Node $v"
  check "node runs as uid 65532" bash -c "[[ \$(docker run --rm $r -p 'process.getuid()') == 65532 ]]"
  check "NODE_ENV=production"    bash -c "[[ \$(docker run --rm $r -p 'process.env.NODE_ENV') == production ]]"
  check "node-runtime has no /bin/sh" bash -c "! docker run --rm --entrypoint /bin/sh $r -c true"
}

while read -r l v; do
  echo "== $l $v"
  common_checks "$l" "$v"
  "verify_$l" "$v"
done < <(selection "$@")

if (( fail == 0 )); then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; exit 1; fi
