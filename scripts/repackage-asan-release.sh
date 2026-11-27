#!/usr/bin/env bash
set -euo pipefail

config="$PWD/config/extensions/${PHP_VERSION:?}"
source scripts/extensions-cache.sh
cache_read_config "$config"
cd "${RUNNER_TEMP:?}"
gh release download "$PHP_VERSION" -R "$GITHUB_REPOSITORY" -p "${PACKAGE:?}.zst"
zstd -qd "$PACKAGE.zst" -o "$PACKAGE"
tar -tf "$PACKAGE" > members
awk -v version="$PHP_VERSION" 'NR == FNR { split($2, ext, "-"); extra[ext[1]] = 1; next }
     split($0, path, "/") == 7 && path[2] == "etc" && path[3] == "php" && path[4] == version && path[6] == "conf.d" && path[7] ~ /^[0-9]+-.*\.ini$/ {
       name = path[7]; sub(/^[0-9]+-/, "", name); sub(/\.ini$/, "", name)
       if (name in extra) print
     }' "$config" members > enabled
for extension in "${cache_names[@]}"; do
  if ! grep -Eq "^\\./usr/lib/php/[^/]+-asan/$extension\\.so$" members; then
    ASAN=asan asan_excludes_extension "$extension" && continue
    echo "Missing $extension.so in $PACKAGE" >&2
    exit 1
  fi
  grep -Fxq "./etc/php/$PHP_VERSION/mods-available/$extension.ini" members
done
if [[ ! -s enabled ]]; then
  echo 'Extra extensions are already disabled.'
  exit 0
fi

tar --delete -f "$PACKAGE" -T enabled
echo "Removed $(wc -l < enabled) extension links"
xz -T0 -4 -ck "$PACKAGE" > "$PACKAGE.xz" &
xz_pid=$!
zstd -q -T0 -12 -f "$PACKAGE" -o "$PACKAGE.zst"
wait "$xz_pid"
gh release upload "$PHP_VERSION" -R "$GITHUB_REPOSITORY" "$PACKAGE.xz" "$PACKAGE.zst" --clobber
