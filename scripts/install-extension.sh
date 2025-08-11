#!/usr/bin/env bash

extension=$1
repo=$2
tag=$3
INSTALL_ROOT=$4
shift 4
params=("$@")

. scripts/patch-extensions.sh

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
    tag=${tag#v}
    cd /tmp/"$(basename "$repo")"-"${tag/\//-}" || exit 1
  fi
  export SED=$(command -v sed)
  patch_"${extension}" 2>/dev/null || true
  phpize
  ./configure "--with-php-config=/usr/bin/php-config" "${params[@]}"
  make -j"$(nproc)"
  make install
  # shellcheck disable=SC2097
  # shellcheck disable=SC2098
  INSTALL_ROOT="$INSTALL_ROOT" make install DESTDIR="$INSTALL_ROOT"
)