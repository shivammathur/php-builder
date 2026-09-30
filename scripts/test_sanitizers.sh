#!/usr/bin/env bash
# Run on Linux: bash scripts/test_sanitizers.sh
set -e

repo=$(cd "$(dirname "$0")/.." && pwd)
# Load helpers without running build actions.
. <(awk '/^if / {exit} {print}' "$repo/scripts/build.sh")
. "$repo/scripts/build_partials/php_build.sh"
. "$repo/scripts/patch-extensions.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/config"
cp -r "$repo/config/definitions" "$tmp/config/definitions"
cd "$tmp"
# Files touched by the SQL Server compatibility patches.
touch init.cpp php_pdo_sqlsrv_int.h pdo_dbh.cpp
php_build_dir="$tmp/php-build"
definitions="$php_build_dir/definitions"
mkdir -p "$definitions" "$php_build_dir/patches"
branch=master
VERSION_ID=24.04

# Keep these checks independent of installed compilers and development packages.
get_buildflags() { echo '-O2'; }
getconf() { :; }
get_c23_standard_flag() { :; }
dpkg-architecture() { echo x86_64-linux-gnu; }
dpkg() {
  if [ "$1" = "-s" ]; then echo 'Version: 76.1'; else command dpkg "$@"; fi
}
configure_option() { options+=("$1${2:+=$2}"); }
patch_file() { :; }
install_package_from_github() { :; }

INSTALL_ROOT="$tmp/staged"
default_ini=production
prefix=/usr
header="$INSTALL_ROOT/usr/include/php/20200930/main/php_config.h"
php-build() {
  mkdir -p "${header%/*}"
  echo '/* Test php-build output. */' > "$header"
  # PHP 8.6+ already exports the arena setting in its installed header.
  if [ "$ASAN" = asan ] && dpkg --compare-versions "$PHP_VERSION" ge 8.6; then
    echo '#define ZEND_TRACK_ARENA_ALLOC 1' >> "$header"
  fi
  cp "$header" "$tmp/original.h"
}

for PHP_VERSION in 8.0 8.1 8.5 8.6 8.7; do
  mkdir -p "config/patches/$PHP_VERSION"
  touch "config/patches/$PHP_VERSION/series"
  for BUILD in nts zts; do
    for ASAN in '' asan; do
      echo "Checking PHP $PHP_VERSION $BUILD ${ASAN:-regular}"
      configure_phpbuild > /dev/null
      options=()
      . "$definitions/$PHP_VERSION"
      expected=''
      if [ "$ASAN" = "asan" ] && [ "$PHP_VERSION" != "8.0" ]; then
        expected=$'--enable-address-sanitizer\n--enable-undefined-sanitizer'
      fi
      actual=$(printf '%s\n' "${options[@]}" | grep sanitizer || true)
      [[ "$actual" = "$expected" ]]

      for target in php extensions; do
        lto=+lto
        configure_build_flags "$target"
        if [ "$ASAN" = "asan" ]; then
          [[ "$lto" = "-lto" ]]
          for flags in "$CFLAGS" "$CXXFLAGS" "$LDFLAGS"; do
            [[ "$flags" = *-fsanitize=address,undefined* ]]
          done
          [[ "$CFLAGS" = *-fno-omit-frame-pointer* && "$CXXFLAGS" = *-fno-omit-frame-pointer* ]]
        else
          [[ "$CFLAGS $CXXFLAGS $LDFLAGS" != *-fsanitize=* ]]
        fi
        for flags in "$CFLAGS" "$CXXFLAGS"; do
          if [ "$ASAN" = "asan" ] && [ "$PHP_VERSION" = "8.0" ]; then
            [[ "$flags" = *-DZEND_TRACK_ARENA_ALLOC* ]]
          else
            [[ "$flags" != *-DZEND_TRACK_ARENA_ALLOC* ]]
          fi
        done
      done

      build_php cli > /dev/null
      if [ "$ASAN" = asan ]; then
        [[ "$(grep -c '^#define ZEND_TRACK_ARENA_ALLOC 1$' "$header")" = 1 ]]
      else
        ! grep -q ZEND_TRACK_ARENA_ALLOC "$header"
      fi
      if [ "$ASAN" != asan ] || dpkg --compare-versions "$PHP_VERSION" ge 8.6; then
        cmp "$header" "$tmp/original.h"
      fi

      for extension in sqlsrv pdo_sqlsrv; do
        (
          expected="$CXXFLAGS"
          [ "$ASAN" != asan ] || expected="$expected -fvisibility=hidden"
          "patch_$extension"
          [[ "$CXXFLAGS" = "$expected" ]]
          [[ "$(bash -c 'printf "%s" "$CXXFLAGS"')" = "$expected" ]]
        )
      done
    done
  done
done

echo 'Sanitizer configuration checks passed.'
