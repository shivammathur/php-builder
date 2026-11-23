#!/usr/bin/env bash
set -euo pipefail

# Pass a PHP source tree after applying this repository's patch series.
source_dir=${1:?Usage: phpize-copy-files.sh /path/to/patched/php-src}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Exercise the actual patched function with isolated source directories.
sed -n '/^phpize_copy_files()/,/^}/p' "$source_dir/scripts/phpize.in" > "$work/copy-files.sh"
grep -q '^phpize_copy_files()' "$work/copy-files.sh"
cat >> "$work/copy-files.sh" <<'COPY'
phpize_copy_files
printf 'completed\n'
COPY
export phpdir="$work/php" aclocaldir="$work/aclocal" auxdir="$work/aux" builddir="$work/extension"
export FILES_BUILD=php.m4 LIBTOOL_FILES=libtool.m4 AUX_FILES=config.guess FILES=run-tests.php
mkdir -p "$phpdir" "$aclocaldir" "$auxdir" "$builddir"
cd "$builddir"

write_sources() {
  printf '%s\n' "$1" > "$phpdir/$FILES_BUILD"
  printf '%s\n' "$1" > "$aclocaldir/$LIBTOOL_FILES"
  printf '%s\n' "$1" > "$auxdir/$AUX_FILES"
  printf '%s\n' "$1" > "$phpdir/$FILES"
}

check_copies() {
  cmp "$phpdir/$FILES_BUILD" "build/$FILES_BUILD"
  cmp "$aclocaldir/$LIBTOOL_FILES" "build/$LIBTOOL_FILES"
  cmp "$auxdir/$AUX_FILES" "build/$AUX_FILES"
  cmp "$phpdir/$FILES" "$FILES"
}

write_sources first
sh "$work/copy-files.sh" > "$work/output"
grep -qx completed "$work/output"
check_copies

# A repeated phpize must replace files installed read-only by a previous run.
chmod a-w "build/$FILES_BUILD" "build/$LIBTOOL_FILES" "build/$AUX_FILES" "$FILES"
write_sources updated
sh "$work/copy-files.sh" > "$work/output"
grep -qx completed "$work/output"
check_copies

# Every copy must fail closed instead of continuing with stale build files.
for file in "$phpdir/$FILES_BUILD" "$aclocaldir/$LIBTOOL_FILES" "$auxdir/$AUX_FILES" "$phpdir/$FILES"; do
  mv "$file" "$file.saved"
  if sh "$work/copy-files.sh" > "$work/output" 2>&1; then
    echo "phpize unexpectedly succeeded without $file" >&2
    exit 1
  fi
  if grep -qx completed "$work/output"; then
    echo "phpize continued after failing to copy $file" >&2
    exit 1
  fi
  mv "$file.saved" "$file"
done

echo 'phpize copy checks passed (initial, read-only repeat, four failure paths)'
