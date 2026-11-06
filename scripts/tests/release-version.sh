#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# Exercise the release entry point without network access or publication.
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RELEASE_CALLS"
case "$*" in
  'release download '*) printf 'previous build\n' > build.log ;;
esac
SH
cat > "$work/bin/curl" <<'SH'
#!/usr/bin/env bash
echo 'Version logging must not query upstream' >&2
exit 1
SH
cat > "$work/bin/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
export GITHUB_MESSAGE='' PHP_SOURCE=--web-php

start_case() {
  mkdir -p "$work/$1/builds/packages" "$work/$1/scripts"
  cd "$work/$1"
  cp "$repo/scripts/retry.sh" "$repo/scripts/install.sh" scripts/
  export PHP_LIST=$2 RELEASE_CALLS="$PWD/release-calls"
  : > "$RELEASE_CALLS"
}

package() {
  local archive=$1 version=$2
  mkdir -p root/usr/include/php/20260924/main
  printf '#define PHP_VERSION "%s"\n' "$version" > root/usr/include/php/20260924/main/php_version.h
  tar -cJf "builds/packages/$archive" -C root ./usr
}

expect_log() {
  bash "$repo/scripts/release.sh" > output 2>&1 || { cat output; exit 1; }
  [ "$(cat "php$PHP_LIST.log")" = "$1" ]
  grep -q '^release upload ' "$RELEASE_CALLS"
}

expect_failure() {
  printf 'previous version\n' > "php$PHP_LIST.log"
  if bash "$repo/scripts/release.sh" > output 2>&1; then
    echo "Release unexpectedly succeeded in $PWD" >&2
    exit 1
  fi
  [ "$(cat "php$PHP_LIST.log")" = 'previous version' ]
  [ ! -s "$RELEASE_CALLS" ]
}

start_case nightly 8.6
package php_8.6+ubuntu24.04.tar.xz 8.6.0-dev
package php_8.6-zts+ubuntu24.04_arm64.tar.xz 8.6.0-dev
# Debug symbols and extension caches must not be treated as runtime packages.
touch builds/packages/php_8.6-dbgsym+ubuntu24.04.tar.xz
touch builds/packages/php_8.6-extensions-cache+ubuntu24.04.tar.zst
expect_log 8.6.0-dev

start_case stable 8.5
package php_8.5+ubuntu22.04.tar.xz 8.5.13
expect_log php-8.5.13

start_case legacy 5.6
package php_5.6+ubuntu22.04.tar.xz 5.6.40
expect_log php-5.6.40

start_case prerelease 8.6
package php_8.6-zts+ubuntu24.04.tar.xz 8.6.0RC2-dev
expect_log 8.6.0RC2-dev

start_case master 8.7
package php_8.7+ubuntu24.04.tar.xz 8.7.0-dev
expect_log 8.7.0-dev

start_case mixed-versions 8.6
package php_8.6+ubuntu24.04.tar.xz 8.6.0-dev
package php_8.6-zts+ubuntu24.04.tar.xz 8.6.1-dev
expect_failure

start_case wrong-series 8.6
package php_8.6+ubuntu24.04.tar.xz 8.7.0-dev
expect_failure

start_case invalid-version 8.6
package php_8.6+ubuntu24.04.tar.xz invalid
expect_failure

start_case missing-header 8.6
mkdir empty
tar -cJf builds/packages/php_8.6+ubuntu24.04.tar.xz -C empty .
expect_failure

start_case corrupt-archive 8.6
printf 'invalid archive\n' > builds/packages/php_8.6+ubuntu24.04.tar.xz
expect_failure

start_case no-runtime 8.6
touch builds/packages/php_8.6-dbgsym+ubuntu24.04.tar.xz
expect_failure

start_case cache-only 8.6
touch builds/packages/php_8.6-extensions-cache+ubuntu24.04.tar.zst
EXTENSIONS_CACHE_ONLY=true bash "$repo/scripts/release.sh" > output 2>&1
[ ! -f php8.6.log ]
grep -q '^release upload ' "$RELEASE_CALLS"

echo 'Release version checks passed (12 cases)'
