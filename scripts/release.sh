#!/usr/bin/env bash

# Function to update the build log
log_build() {
  gh release download "$PHP_VERSION" -p "build.log" || true
  date '+%Y.%m.%d' | sudo tee -a build.log
  assets+=("./build.log")
}

# Record the version actually packaged, even if upstream advances before release.
log_version() {
  local asset package_version new_version=
  for asset in "${assets[@]}"; do
    case "${asset##*/}" in
      php_"$PHP_VERSION"+*.tar.xz|php_"$PHP_VERSION"-zts+*.tar.xz) ;;
      *) continue ;;
    esac
    package_version=$(set -o pipefail; tar -xJOf "$asset" --wildcards './usr/include/php/*/main/php_version.h' |
      sed -nE 's/^#define PHP_VERSION "([^"]+)"$/\1/p') || return 1
    if [[ ! "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+((alpha|beta|RC)[0-9]+)?(-dev)?$ ]] ||
       [[ "$package_version" != "$PHP_VERSION".* ]]; then
      echo "Invalid PHP $PHP_VERSION version in $asset: $package_version" >&2
      return 1
    fi
    if [ -n "$new_version" ] && [ "$new_version" != "$package_version" ]; then
      echo "PHP $PHP_VERSION packages disagree: $new_version and $package_version ($asset)" >&2
      return 1
    fi
    new_version=$package_version
  done
  if [ -z "$new_version" ]; then
    echo "No PHP $PHP_VERSION runtime package found for the version log" >&2
    return 1
  fi
  # Stable-build checks compare this log with upstream tag names.
  [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && new_version="php-$new_version"
  printf '%s\n' "$new_version" > "php$PHP_VERSION.log" || return 1
  assets+=("scripts/install.sh" "./php$PHP_VERSION.log")
}

# Exit if commit message has skip-release.
[[ "$GITHUB_MESSAGE" = *skip-release* ]] && exit 0;

# Remove intermediate builds.
rm -rf ./builds/php-sapi* ./builds/php-base* ./builds/php-extensions*

IFS=' ' read -r -a PHP_VERSIONS <<<"${PHP_LIST:?}"
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
  # Build assets array with builds.
  shopt -s nullglob
  assets=()
  if [ "${EXTENSIONS_CACHE_ONLY:-false}" = true ]; then
    assets=(./builds/*/php_"$PHP_VERSION"-extensions-cache+*.tar.zst
            ./builds/*/php_"$PHP_VERSION"-zts-extensions-cache+*.tar.zst)
    [ "${#assets[@]}" -gt 0 ] || { echo "No extension caches for PHP $PHP_VERSION" >&2; exit 1; }
  else
    for asset in ./builds/*/php_"$PHP_VERSION"*; do
      assets+=("$asset")
    done
  fi
  shopt -u nullglob
  if [ "${#assets[@]}" -ne 0 ]; then
    # Update logs.
    if [ "${EXTENSIONS_CACHE_ONLY:-false}" != true ]; then
      log_version || exit 1
      log_build
    fi

    # Create or update release.
    if ! gh release view "$PHP_VERSION"; then
      bash scripts/retry.sh 5 5 gh release create "$PHP_VERSION" "${assets[@]}" -t "$PHP_VERSION" -n "$PHP_VERSION"
    else
      bash scripts/retry.sh 5 5 gh release upload "$PHP_VERSION" "${assets[@]}" --clobber
    fi
  fi
done
