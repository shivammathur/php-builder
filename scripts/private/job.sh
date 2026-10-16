#!/usr/bin/env bash
set -euo pipefail
[ "${GITHUB_ACTIONS:-}" = true ] || { echo 'Private jobs require disposable Actions runners'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
case "$1" in
  sapi)
    bash scripts/install-requirements.sh
    mkdir -p "$PHP_BUILD_TMPDIR"
    bash scripts/build.sh build_sapi "$SAPI"
    ;;
  package)
    bash scripts/install-requirements.sh
    mkdir -p /tmp/debian
    for archive in "$PRIVATE_WORK"/sapis/*.zst; do
      tar -I zstd -xf "$archive" -C /tmp/debian
    done
    bash scripts/build.sh merge
    bash scripts/build.sh build_extensions
    bash scripts/build.sh package
    [ "$(php -n -r 'echo PHP_VERSION;')" = "$PHP_PRIVATE_RELEASE_VERSION" ]
    php-cgi -v
    php-fpm -v
    php-fpm -t
    phpdbg -V
    pecl -V
    phpize -v
    bash scripts/test_extensions.sh
    ;;
  test)
    runner=local
    [ "$PRIVATE_TEST_KIND" = host ] && runner=github
    bash "$PHP_BUILDER_ARCHIVE_DIR/install.sh" "$PHP_VERSION" "$runner" "$BUILDS" "$TS"
    [ "$(php -n -r 'echo PHP_VERSION;')" = "$PHP_PRIVATE_RELEASE_VERSION" ]
    [ "$(php -n -r 'echo PHP_ZTS ? "zts" : "nts";')" = "$TS" ]
    php -m
    php -r 'print_r(gd_info());'
    bash scripts/test_pecl.sh
    bash scripts/test_sapi.sh
    ;;
  *) exit 1 ;;
esac
