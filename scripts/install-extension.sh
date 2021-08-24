#!/usr/bin/env bash

# Function to patch imagick source.
patch_imagick() {
  sed -i 's/spl_ce_Countable/zend_ce_countable/' imagick.c util/checkSymbols.php
  sed -i "s/@PACKAGE_VERSION@/$(grep -Po 'release>\K(\d+\.\d+\.\d+)' package.xml)/" php_imagick.h
}

# Function to patch sqlsrv source.
patch_sqlsrv() {
  cd source/sqlsrv || exit 1
  cp -rf ../shared ./
}

# Function to patch pdo_sqlsrv source.
patch_pdo_sqlsrv() {
  cd source/pdo_sqlsrv || exit 1
  cp -rf ../shared ./
}

extension=$1
repo=$2
tag=$3
INSTALL_ROOT=$4
shift 4
params=("$@")

# Fetch the extension source.
curl -o "/tmp/$extension.tar.gz" -sSL "$repo/archive/$tag.tar.gz"

# Extract it to /tmp and build the extension in INSTALL_ROOT
tar xf "/tmp/$extension.tar.gz" -C /tmp
(
  cd /tmp/"$(basename "$repo")"-"$tag" || exit 1
  patch_"${extension}" 2>/dev/null || true
  phpize
  ./configure "--with-php-config=/usr/bin/php-config" "${params[@]}"
  make -j"$(nproc)"
  make install
  # shellcheck disable=SC2097
  # shellcheck disable=SC2098
  INSTALL_ROOT="$INSTALL_ROOT" make install DESTDIR="$INSTALL_ROOT"
)