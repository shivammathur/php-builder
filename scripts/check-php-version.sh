#!/usr/bin/env bash

# Put input PHP versions in array php_versions_to_check.
IFS=' ' read -r -a php_versions_to_check <<<"$1"

# Find which PHP versions need to be built.
php_versions_to_build=()
if [[ "$2" = *build-all* ]]; then
  php_versions_to_build=("${php_versions_to_check[@]}")
else
  for php_version in "${php_versions_to_check[@]}"; do
    # Fetch new and existing version, compare and add to php_versions_to_build array.
    existing_version=$(curl -sL https://github.com/shivammathur/php-builder/releases/latest/download/php"$php_version".log)
    new_version=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($php_version.[0-9]+)" | head -n 1)
    if [ "$new_version" != "$existing_version" ]; then
      php_versions_to_build+=("$php_version")
    fi
  done
fi

# Output the PHP versions which have to be built.
echo "${php_versions_to_build[@]}"