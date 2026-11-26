#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
. /etc/os-release
base="https://github.com/${GITHUB_REPOSITORY:?}/releases/download/zstd"
version=$(curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 --max-time 120 "$base/version.txt")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
asset="zstd-$version-$ID-$VERSION_ID-$(dpkg --print-architecture)"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 --max-time 120 "$base/$asset" -o "$tmp"
chmod 755 "$tmp"
test "$("$tmp" -q --version)" = "$version"
install -m 755 "$tmp" /usr/local/bin/zstd
test "$(zstd -q --version)" = "$version"
zstd -V
