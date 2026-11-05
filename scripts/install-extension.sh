#!/usr/bin/env bash

extension=$1
repo=$2
tag=$3
INSTALL_ROOT=$4
shift 4
params=("$@")
pecl_package=$extension
PHP_INSTALL_ROOT="${PHP_INSTALL_ROOT:-$INSTALL_ROOT}"

case "$extension" in
  http)
    pecl_package=pecl_http
    ;;
esac

. scripts/patch-extensions.sh

. scripts/extension-source.sh

download_git_archive() {
  local archive_url encoded_tag output
  output="/tmp/$extension.tar.gz"
  encoded_tag="${tag//\//%2f}"

  for archive_url in "$repo/archive/$encoded_tag.tar.gz" "$repo/archive/refs/tags/$encoded_tag.tar.gz"; do
    rm -f "$output"
    if curl -fsSL --retry 5 --retry-all-errors -o "$output" "$archive_url" && tar -tzf "$output" >/dev/null 2>&1; then
      return 0
    fi
  done

  echo "Could not download a valid archive for $extension from $repo at $tag" >&2
  return 1
}

download_latest_pecl_archive() {
  local latest_version release_url

  latest_version="$(
    curl -fsSL --retry 5 --retry-all-errors "https://pecl.php.net/rest/r/$pecl_package/allreleases.xml" \
    | sed -n 's/.*<v>\([^<]*\)<\/v>.*/\1/p' \
    | head -n 1
  )"
  if [ -z "$latest_version" ]; then
    echo "Could not determine the latest PECL release for $pecl_package" >&2
    return 1
  fi
  release_url="https://pecl.php.net/get/$pecl_package-$latest_version.tgz"
  curl -fsSL --retry 5 --retry-all-errors -o "$pecl_package-$latest_version.tgz" "$release_url"
}

if [[ "$repo" != "pecl" && "$tag" = "latest" ]]; then
  tag="$(get_latest_git_tag "$repo")" || exit 1
fi

# Clean stale sources from previous local builds of the same extension.
rm -rf /tmp/"$extension"-* /tmp/"$pecl_package"-* /tmp/"$extension".tar.gz "$extension"*.tgz "$pecl_package"*.tgz

# Fetch the extension source.
if [ "$repo" = "pecl" ]; then
  if [ -x "$PHP_INSTALL_ROOT/usr/bin/pecl" ]; then
    "$PHP_INSTALL_ROOT"/usr/bin/pecl channel-update pecl.php.net || true
    if [ -n "${tag// }" ]; then
      "$PHP_INSTALL_ROOT"/usr/bin/pecl download "$pecl_package-$tag" || compgen -G "$pecl_package*.tgz" >/dev/null || exit 1
    else
      "$PHP_INSTALL_ROOT"/usr/bin/pecl download "$pecl_package" || compgen -G "$pecl_package*.tgz" >/dev/null || download_latest_pecl_archive || exit 1
    fi
  elif [ -n "${tag// }" ]; then
    curl -fsSL --retry 5 --retry-all-errors -o "$pecl_package-$tag.tgz" "https://pecl.php.net/get/$pecl_package-$tag.tgz" || exit 1
  else
    download_latest_pecl_archive || exit 1
  fi
  mv "$pecl_package"*.tgz /tmp/"$extension".tar.gz || exit 1
else
  download_git_archive || exit 1
fi

# Extract it to /tmp and build the extension in INSTALL_ROOT
tar xf "/tmp/$extension.tar.gz" -C /tmp || exit 1
(
  if [ "$repo" = "pecl" ]; then
    cd /tmp/"$pecl_package"-* || exit 1
  else
    tag=${tag#v}
    cd /tmp/"$(basename "$repo")"-"${tag/\//-}" || exit 1
  fi
  SED=$(command -v sed) || exit 1
  export SED
  configure_legacy_extension_flags
  if declare -f "patch_${extension}" >/dev/null; then
    "patch_${extension}"
  fi
  phpize || exit 1
  ./configure "--with-php-config=/usr/bin/php-config" "${params[@]}" || exit 1
  make -j"$(nproc)" || exit 1
  make install || exit 1
  # shellcheck disable=SC2097
  # shellcheck disable=SC2098
  INSTALL_ROOT="$INSTALL_ROOT" make install DESTDIR="$INSTALL_ROOT" || exit 1
) || exit 1
