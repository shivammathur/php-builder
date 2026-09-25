#!/usr/bin/env bash
set -euo pipefail

: "${PHP_VERSION:?}"
: "${BUILD:?}"
: "${SOURCE_ARTIFACT_DIR:?}"
: "${EXTENSIONS_TO_BUILD:?}"

suffix=
[ "$BUILD" = zts ] && suffix=-zts
install_root="/tmp/debian/php$PHP_VERSION"
debug_root="${SOURCE_DEBUG_ROOT:-/tmp/source-debug}"
IFS=' ' read -r -a extensions <<<"${EXTENSIONS_TO_BUILD//,/ }"
if [ "${#extensions[@]}" -eq 0 ]; then
  echo 'No extensions specified' >&2
  exit 1
fi
for extension in "${extensions[@]}"; do
  if [[ ! "$extension" =~ ^[[:alnum:]_]+$ ]]; then
    echo "Invalid extension: $extension" >&2
    exit 1
  fi
done

mapfile -t package_archives < <(find "$SOURCE_ARTIFACT_DIR" -maxdepth 1 -type f -name "php_${PHP_VERSION}${suffix}+*.tar.zst" | sort)
mapfile -t debug_archives < <(find "$SOURCE_ARTIFACT_DIR" -maxdepth 1 -type f -name "php_${PHP_VERSION}${suffix}-dbgsym+*.tar.zst" | sort)
if [ "${#package_archives[@]}" -ne 1 ] || [ "${#debug_archives[@]}" -ne 1 ]; then
  echo "Expected one PHP package and one debug package for PHP $PHP_VERSION $BUILD" >&2
  exit 1
fi

mkdir -p "$install_root" "$debug_root"
tar -I zstd -xf "${package_archives[0]}" -C "$install_root"
tar -I zstd -xf "${debug_archives[0]}" -C "$debug_root" ./usr/lib/debug/.build-id
test -x "$install_root/usr/bin/php$PHP_VERSION"

# The rebuilt extensions get fresh debug symbols. Discard their old symbols.
for extension in "${extensions[@]}"; do
  mapfile -t binaries < <(find "$install_root/usr/lib/php" -type f -name "$extension.so")
  if [ "${#binaries[@]}" -gt 1 ]; then
    echo "Found multiple $extension.so files in the source package" >&2
    exit 1
  fi
  [ "${#binaries[@]}" -eq 1 ] || continue
  build_id="$(readelf -n "${binaries[0]}" | sed -n 's/.*Build ID: //p' | head -n 1)"
  if [ -n "$build_id" ]; then
    old_debug="$debug_root/usr/lib/debug/.build-id/${build_id:0:2}/${build_id:2}.debug"
    if [ -f "$old_debug" ]; then
      rm "$old_debug"
    fi
  fi
done

# Install PHP using the same archive extraction as scripts/install.sh. The
# release also contains library overlays, so copying the whole tree to /
# while cp is running can replace a library loaded by cp.
tar -I zstd -xf "${package_archives[0]}" -C / --no-same-owner
