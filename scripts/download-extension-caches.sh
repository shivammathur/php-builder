#!/usr/bin/env bash
set -euo pipefail

: "${PHP_VERSION:?}" "${PACKAGE_RUN_ID:?}" "${GITHUB_REPOSITORY:?}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p builds/extension-caches

gh api "repos/$GITHUB_REPOSITORY/actions/runs/$PACKAGE_RUN_ID/artifacts?per_page=100" \
  --paginate > "$work/artifacts.json"
mapfile -t artifacts < <(jq -r --arg prefix "php$PHP_VERSION-" \
  '.artifacts[] | select(.expired == false and (.name | startswith($prefix))) | .name' "$work/artifacts.json")
[ "${#artifacts[@]}" -gt 0 ] || { echo 'No packaged extension caches found' >&2; exit 1; }

# Full package artifacts include both compression formats and debug packages.
# Keep only their caches, downloading one artifact at a time to bound disk use.
shopt -s nullglob
for artifact in "${artifacts[@]}"; do
  mkdir "$work/package"
  gh run download "$PACKAGE_RUN_ID" --repo "$GITHUB_REPOSITORY" --name "$artifact" --dir "$work/package"
  caches=("$work/package/php_$PHP_VERSION-extensions-cache+"*.tar.zst
          "$work/package/php_$PHP_VERSION-zts-extensions-cache+"*.tar.zst
          "$work/package/php_$PHP_VERSION-asan-extensions-cache+"*.tar.zst
          "$work/package/php_$PHP_VERSION-zts-asan-extensions-cache+"*.tar.zst)
  [ "${#caches[@]}" -eq 1 ] || { echo "Expected one extension cache in $artifact" >&2; exit 1; }
  destination="builds/extension-caches/${caches[0]##*/}"
  [ ! -e "$destination" ] || { echo "Duplicate extension cache: $destination" >&2; exit 1; }
  mv "${caches[0]}" "$destination"
  rm -rf "$work/package"
done
