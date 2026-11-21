#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Load the real installer functions without running the command-line entry point.
printf 'ID=ubuntu\n' > "$work/os-release"
source <(sed -e '/^# avoid running without arguments/,$d' \
  -e "s|/etc/os-release|$work/os-release|g" "$repo/scripts/install.sh")

# Keep the install flow and extraction routing real, with no host writes/network.
sudo() { printf '%s\n' "$*" >> "$work/calls"; }
get() { :; }
add_prerequisites() { :; }
github_deps() { :; }
local_deps() { :; }
update_brotli_security() { :; }
set_base_version() { DIST_ID="$ID"; ID=ubuntu; VERSION_ID=22.04; }
relocate_build() { printf 'relocate %s\n' "$1" >> "$work/calls"; }

version=7.0
PHP_PKG_SUFFIX=-zts-dbgsym
for mode in github local; do
  for distro in ubuntu debian linuxmint; do
    : > "$work/calls"
    ID=$distro VERSION_ID=22.04
    unset DIST_ID
    install "$mode"
    if [[ $distro = ubuntu || $distro = debian ]]; then
      grep -q ' -C / --no-same-owner$' "$work/calls"
      ! grep -q '^relocate ' "$work/calls"
    else
      grep -q ' -C /tmp/php7.0 --no-same-owner$' "$work/calls"
      grep -q '^relocate /tmp/php7.0$' "$work/calls"
    fi
  done
done
echo 'Installer platform routing checks passed (6 cases)'
