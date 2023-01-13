#!/usr/bin/env bash

# Function to patch imagick source.
patch_imagick() {
  sed -i 's/spl_ce_Countable/zend_ce_countable/' imagick.c util/checkSymbols.php
  sed -i "s/@PACKAGE_VERSION@/$(grep -Po 'release>\K(\d+\.\d+\.\d+)' package.xml)/" php_imagick.h
}

# Function to patch sqlsrv source.
patch_sqlsrv() {
  if [ -d source/sqlsrv ]; then
    cd source/sqlsrv || exit 1
    cp -rf ../shared ./
  fi
}

# Function to patch pdo_sqlsrv source.
patch_pdo_sqlsrv() {
  if [ -d source/pdo_sqlsrv ]; then
    cd source/pdo_sqlsrv || exit 1
    cp -rf ../shared ./
  fi
}

patch_xdebug() {
  # Patch for xdebug on PHP 8.3.
  sed -i 's/80300/80400/g' config.m4
}

patch_amqp() {
  [ "$PHP_VERSION" = "8.3" ] && sed -i "s/#include <amqp.h>/#include <errno.h>\n#include <amqp.h>/" php_amqp.h
}

patch_memcache() {
  [ "$PHP_VERSION" = "8.3" ] && sed -i "s/#include <string.h>/#include <string.h>\n#include <errno.h>/" src/memcache_pool.h
}

patch_memcached() {
  [ "$PHP_VERSION" = "8.3" ] && sed -i "s/#include \"php.h\"/#include <errno.h>\n#include \"php.h\"/" php_memcached.h
}

patch_redis() {
  [ "$PHP_VERSION" = "8.3" ] && sed -i "s/#include <sys\/types.h>/#include <errno.h>\n#include <sys\/types.h>/" library.c
}

extension=$1
repo=$2
tag=$3
INSTALL_ROOT=$4
shift 4
params=("$@")

# Fetch the extension source.
if [ "$repo" = "pecl" ]; then
  if [ -n "${tag// }" ]; then
    "$INSTALL_ROOT"/usr/bin/pecl download "$extension-$tag"
  else
    "$INSTALL_ROOT"/usr/bin/pecl download "$extension"
  fi
  mv "$extension"*.tgz /tmp/"$extension".tar.gz
else
  curl -o "/tmp/$extension.tar.gz" -sSL "$repo/archive/${tag/\//%2f}.tar.gz"
fi

# Extract it to /tmp and build the extension in INSTALL_ROOT
tar xf "/tmp/$extension.tar.gz" -C /tmp
(
  if [ "$repo" = "pecl" ]; then
    cd /tmp/"$extension"-* || exit 1
  else
    cd /tmp/"$(basename "$repo")"-"${tag/\//-}" || exit 1
  fi
  patch_"${extension}" 2>/dev/null || true
  phpize
  ./configure "--with-php-config=/usr/bin/php-config" "${params[@]}"
  make -j"$(nproc)"
  make install
  # shellcheck disable=SC2097
  # shellcheck disable=SC2098
  INSTALL_ROOT="$INSTALL_ROOT" make install DESTDIR="$INSTALL_ROOT"
)