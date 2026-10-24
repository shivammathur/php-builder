#!/usr/bin/env bash
set -e

# GitHub source archives omit the corpus needed by the upstream test suites.
curl --retry 5 --retry-all-errors -fsSL \
  https://github.com/google/brotli/releases/download/v1.2.1/testdata.txz -o testdata.txz
echo '00a4375c03b7cf6bdb71ecb9ad6bec847f23affd52f27e75270efaf720219589  testdata.txz' | sha256sum -c -
tar -xf testdata.txz
rm testdata.txz

# A native arm64 compiler can have a triplet prefix too; only cross builds need QEMU.
# shellcheck disable=SC2016
sed -i 's/if ("${CMAKE_C_COMPILER}"/if (CMAKE_CROSSCOMPILING AND "${CMAKE_C_COMPILER}"/' CMakeLists.txt
