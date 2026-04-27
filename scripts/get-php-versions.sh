#!/usr/bin/env bash
set -e

php_versions="$(bash scripts/check-php-version.sh "${PHP_LIST:?}" "${COMMIT:-'--build-new'}" "${PHP_SOURCE:-'--web-php'}")"

if [ -n "${php_versions// }" ]; then
  has_versions=true
  php_versions_json="$(printf '%s\n' "$php_versions" | tr ' ' '\n' | jq -R . | jq -cs .)"
else
  has_versions=false
  php_versions_json='[]'
fi

{
  echo "has_versions=$has_versions"
  echo "php_versions=$php_versions_json"
} >> "$GITHUB_OUTPUT"
