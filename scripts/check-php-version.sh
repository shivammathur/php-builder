#!/usr/bin/env bash

# Function to get the latest stable release tag for a PHP version.
get_stable_release_tag() {
  source=$1
  if [ "$source" = "--web-php" ]; then
    release_tag="$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-(${php_version//./\\.}\.[0-9]+)" | head -n 1)"
    echo "${release_tag:-$(curl -sL https://www.php.net/releases | grep -Po "<h2>\K${php_version//./\\.}\.[0-9]+" | head -n1 | sed 's/^/php-/')}"
  else
    curl -H "Authorization: Bearer $GITHUB_TOKEN" -sL "https://api.github.com/repos/php/php-src/git/matching-refs/tags%2Fphp-$php_version." | grep -Eo "php-[0-9]+\.[0-9]+\.[0-9]+\"" | sort -V | tail -1 | cut -d '"' -f 1
  fi
}

# Put input PHP versions in array php_versions_to_check.
IFS=' ' read -r -a php_versions_to_check <<<"$1"

# Find which PHP versions need to be built.
php_versions_to_build=()
if [[ "$2" = *build-all* ]]; then
  php_versions_to_build=("${php_versions_to_check[@]}")
else
  for php_version in "${php_versions_to_check[@]}"; do
    # Fetch new and existing version, compare and add to php_versions_to_build array.
    # Here we only check for stable as both RC and nightly should be built.
    existing_version=$(curl -sL https://github.com/shivammathur/php-builder/releases/download/"$php_version"/php"$php_version".log)
    new_version="$(get_stable_release_tag "$3")"
    if [ "$new_version" != "$existing_version" ]; then
      php_versions_to_build+=("$php_version")
    fi
  done
fi

# Output the PHP versions which have to be built.
echo "${php_versions_to_build[@]}"