#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/../.." && pwd)
# shellcheck source=/dev/null
. /etc/os-release

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gcc libc6-dev libbrotli-dev pkg-config

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
multiarch=$(gcc -print-multiarch)

if [ "$ID" = ubuntu ]; then
  artifact_dir=${1:?Pass the directory containing built Brotli packages}
  # shellcheck source=config/lib/brotli
  . "$repo_dir/config/lib/brotli"
  expected_version=${LIB_UPSTREAM_REF#v}
  for package in "${LIB_BINARY_PACKAGES[@]}"; do
    debs=("$artifact_dir/$package"_*.deb)
    [ "${#debs[@]}" = 1 ]
    [ -f "${debs[0]}" ]
    dpkg --compare-versions "$(dpkg-deb -f "${debs[0]}" Version)" eq "$LIB_PACKAGE_VERSION"
    [ "$(dpkg-deb -f "${debs[0]}" Architecture)" = "$(dpkg --print-architecture)" ]
    dpkg-deb -I "${debs[0]}"
  done

  # Exercise the same extraction and staging paths used for PHP build artifacts.
  export LIBRARIES_BASE_URL="file://$artifact_dir"
  export LIBRARIES_DOWNLOAD_DIR="$work_dir/downloads"
  bash "$script_dir/install.sh" --library brotli --root "$work_dir/root" --manifest "$work_dir/manifest"
  test -s "$work_dir/root/usr/include/brotli/decode.h"
  grep -q 'libbrotlidec.so' "$work_dir/manifest"
  bash "$script_dir/install.sh" --library brotli
else
  # shellcheck source=scripts/lib/brotli-security.sh
  . "$script_dir/brotli-security.sh"
  check_debian_brotli_security
  expected_version=$(pkg-config --modversion libbrotlidec)
  # Debian must not try to download or stage the Ubuntu overlay.
  bash "$script_dir/install.sh" --library brotli --root "$work_dir/root" --manifest "$work_dir/manifest"
  test ! -s "$work_dir/manifest"
fi

test "$(pkg-config --modversion libbrotlidec)" = "$expected_version"
cat > "$work_dir/roundtrip.c" <<'C'
#include <brotli/decode.h>
#include <brotli/encode.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  const uint8_t input[] = "PHP Builder Brotli artifact roundtrip";
  uint8_t encoded[256], decoded[256];
  size_t encoded_size = sizeof(encoded), decoded_size = sizeof(decoded);
  unsigned major, minor, patch;
  if (argc != 2 || sscanf(argv[1], "%u.%u.%u", &major, &minor, &patch) != 3) return 1;
  uint32_t expected = (major << 24) | (minor << 12) | patch;
  if (BrotliDecoderVersion() != expected || BrotliEncoderVersion() != expected) return 2;
  if (!BrotliEncoderCompress(5, 22, BROTLI_MODE_GENERIC, sizeof(input), input,
                            &encoded_size, encoded)) return 3;
  if (BrotliDecoderDecompress(encoded_size, encoded, &decoded_size, decoded)
      != BROTLI_DECODER_RESULT_SUCCESS) return 4;
  if (decoded_size != sizeof(input) || memcmp(input, decoded, sizeof(input))) return 5;
  printf("Brotli %s roundtrip passed\n", argv[1]);
  return 0;
}
C
# shellcheck disable=SC2046
gcc -Wall -Wextra -Werror "$work_dir/roundtrip.c" $(pkg-config --cflags --libs libbrotlienc libbrotlidec) -o "$work_dir/shared"
"$work_dir/shared" "$expected_version"
ldd "$work_dir/shared"
gcc -Wall -Wextra -Werror "$work_dir/roundtrip.c" \
  "/usr/lib/$multiarch/libbrotlienc.a" "/usr/lib/$multiarch/libbrotlidec.a" \
  "/usr/lib/$multiarch/libbrotlicommon.a" -lm -o "$work_dir/static"
"$work_dir/static" "$expected_version"
# Verify the prebuilt distro curl still loads and reports the replacement library.
curl --version | tee "$work_dir/curl-version"
grep -q "brotli/$expected_version" "$work_dir/curl-version"
