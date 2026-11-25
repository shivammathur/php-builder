#!/usr/bin/env bash
set -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$PHP_VERSION" = "5.6" ]; then
  package=uuid-1.0.5
else
  package=uuid
fi

# Retry PECL metadata/archive fetches without retrying compilation or installation.
download_dir="$(mktemp -d)"
trap 'rm -rf "$download_dir"' EXIT
cd "$download_dir"
bash "$script_dir/retry.sh" 5 5 sudo pecl download "$package"
sudo pecl install -f ./uuid-*.tgz
php --ri uuid
