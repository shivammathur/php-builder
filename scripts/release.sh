#!/usr/bin/env bash

# Function to update the build log
log_build() {
  gh release download "$PHP_VERSION" -p "build.log" || true
  date '+%Y.%m.%d' | sudo tee -a build.log
  assets+=("./build.log")
}

# Function to get the latest stable release tag for a PHP version.
get_stable_release_tag() {
  source=$1
  if [ "$source" = "--web-php" ]; then
    release_tag="$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-(${PHP_VERSION//./\\.}\.[0-9]+)" | head -n 1)"
    echo "${release_tag:-$(curl -sL https://www.php.net/releases | grep -Po "${PHP_VERSION//./\\.}\.[0-9]+" | head -n1 | sed 's/^/php-/')}"
  else
    curl -H "Authorization: Bearer $GITHUB_TOKEN" -sL "https://api.github.com/repos/php/php-src/git/matching-refs/tags%2Fphp-$PHP_VERSION." | grep -Eo "php-[0-9]+\.[0-9]+\.[0-9]+\"" | sort -V | tail -1 | cut -d '"' -f 1
  fi
}

# Function to get the PHP version from a branch.
get_version_from_branch() {
  curl -sL https://raw.githubusercontent.com/php/php-src/"$1"/main/php_version.h | grep -Po 'PHP_VERSION "\K[0-9]+\.[0-9]+\.[0-9][0-9a-zA-Z-]*' 2>/dev/null || true
}

# Function to update the PHP version log
log_version() {
  assets+=("scripts/install.sh")
  new_version=$(get_stable_release_tag "$PHP_SOURCE")
  if [ "$new_version" = "" ]; then
    new_version=$(get_version_from_branch PHP-"$PHP_VERSION")
    if [ "$new_version" = "" ]; then
      new_version=$(get_version_from_branch master)
    fi
  fi
  echo "$new_version" > "php$PHP_VERSION.log"
  assets+=("./php$PHP_VERSION.log")
}

# Exit if commit message has skip-release.
[[ "$GITHUB_MESSAGE" = *skip-release* ]] && exit 0;

# Remove SAPI builds.
rm -rf ./builds/php-sapi*

IFS=' ' read -r -a PHP_VERSIONS <<<"${PHP_LIST:?}"
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
  # Build assets array with builds.
  shopt -s nullglob
  assets=()
  for asset in ./builds/*/php_"$PHP_VERSION"*; do
    assets+=("$asset")
  done
  shopt -u nullglob
  if [ "${#assets[@]}" -ne 0 ]; then
    # Update logs.
    log_version
    log_build

    # Create or update release.
    if ! gh release view "$PHP_VERSION"; then
      bash scripts/retry.sh 5 5 gh release create "$PHP_VERSION" "${assets[@]}" -t "$PHP_VERSION" -n "$PHP_VERSION"
    else
      bash scripts/retry.sh 5 5 gh release upload "$PHP_VERSION" "${assets[@]}" --clobber
    fi
  fi
done
