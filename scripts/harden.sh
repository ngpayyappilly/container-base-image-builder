#!/bin/sh
# Shared hardening for every Debian/Ubuntu-based stage we own.
# (Distroless stages are already minimal and are not touched by this script.)
#
#   harden.sh build     builder image: add the unprivileged user, drop setuid bits
#   harden.sh runtime   runtime image: the above, plus patch, de-tool and lock down
#
# Env:  EXTRA_PACKAGES  space separated apt packages to install (runtime only)
#
# Run it from a single RUN instruction so all of it lands in ONE layer.
set -eu

mode=${1:?usage: harden.sh build|runtime}
case "$mode" in build|runtime) ;; *) echo "bad mode: $mode" >&2; exit 2 ;; esac

# 65532 is what distroless calls "nonroot". Using the same numeric uid/gid in
# every image means one Kubernetes runAsUser and one COPY --chown for all.
UID_GID=65532
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------- user ----
getent group  "$UID_GID" >/dev/null || groupadd --gid "$UID_GID" nonroot
getent passwd "$UID_GID" >/dev/null || useradd \
  --uid "$UID_GID" --gid "$UID_GID" \
  --home-dir /home/nonroot --create-home \
  --shell /usr/sbin/nologin nonroot
chmod 0700 /home/nonroot

# ----------------------------------------------------------- packages ----
apt-get update
# Pick up Debian/Ubuntu security fixes that landed after the upstream image was cut.
apt-get -y --no-install-recommends upgrade
if [ "$mode" = runtime ] && [ -n "${EXTRA_PACKAGES:-}" ]; then
  # shellcheck disable=SC2086  # intentional word splitting
  apt-get -y --no-install-recommends install $EXTRA_PACKAGES
fi
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/cache/debconf/* /var/log/*

# ------------------------------------------------------ setuid / setgid ----
# Nothing in a container should be able to change identity via a file bit.
find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -exec chmod a-s {} +

if [ "$mode" = runtime ]; then
  # ---------------------------------------- remove post-exploit tooling ----
  # Package manager: nobody should `apt install` inside a running container.
  # /var/lib/dpkg/status is KEPT so scanners (Trivy, Grype) can still read the
  # package inventory - that is exactly what distroless does too.
  rm -f /usr/bin/apt /usr/bin/apt-* /usr/bin/dpkg /usr/bin/dpkg-* \
        /usr/sbin/dpkg-* /usr/bin/debconf*
  # Identity / mount helpers that are only useful for privilege escalation.
  rm -f /bin/su /usr/bin/su /usr/bin/chsh /usr/bin/chfn /usr/bin/newgrp \
        /usr/bin/gpasswd /usr/bin/passwd /usr/bin/mount /bin/mount \
        /usr/bin/umount /bin/umount /usr/bin/wall /usr/bin/write

  # Docs: keep the licence files (redistribution requirement), drop the rest.
  find /usr/share/doc -type f ! -name copyright -delete 2>/dev/null || true
  find /usr/share/doc -type d -empty -delete 2>/dev/null || true
  rm -rf /usr/share/man /usr/share/info /usr/share/lintian /usr/share/locale/*

  # root cannot be logged into; the container user is the only way in.
  sed -i -E 's#^(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:).*$#\1/usr/sbin/nologin#' /etc/passwd
  sed -i -E 's#^(root:)[^:]*:#\1*:#' /etc/shadow
fi

# (the script itself is bind-mounted at /tmp/harden.sh by the Dockerfiles - skip it)
find /tmp /var/tmp -mindepth 1 ! -name harden.sh -exec rm -rf {} + 2>/dev/null || true
