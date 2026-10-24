#!/usr/bin/env bash

# Debian backports CVE-2026-111497 without changing the upstream Brotli version.
check_debian_brotli_security() {
  local minimum package version architecture
  case "$ID-$VERSION_ID" in
    debian-12) minimum=1.0.9-2+deb12u1 ;;
    debian-13) minimum=1.1.0-2+deb13u1 ;;
    *) return 0 ;;
  esac
  architecture=$(dpkg --print-architecture) || return 1
  for package in libbrotli1 libbrotli-dev; do
    version=$(dpkg-query -W -f='${Version}' "$package:$architecture") || return 1
    if ! dpkg --compare-versions "$version" ge "$minimum"; then
      printf 'Error: %s %s is vulnerable to CVE-2026-111497; enable %s-security and install >= %s.\n' \
        "$package" "$version" "$VERSION_CODENAME" "$minimum" >&2
      return 1
    fi
    printf 'Verified %s=%s fixes CVE-2026-111497\n' "$package" "$version"
  done
}
