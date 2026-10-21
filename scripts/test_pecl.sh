#!/usr/bin/env bash
set -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$PHP_VERSION" = "5.6" ]; then
  package=psr-0.6.0
elif [[ "$PHP_VERSION" =~ 7.[0-2]$ ]]; then
  package=psr-1.1.0
else
  package=psr
fi

# Retry PECL metadata/archive fetches without retrying compilation or installation.
download_dir="$(mktemp -d)"
trap 'rm -rf "$download_dir"' EXIT
cd "$download_dir"
bash "$script_dir/retry.sh" 5 5 sudo pecl download "$package"
sudo pecl install -f ./psr-*.tgz
php -m | grep -q psr || exit 1
