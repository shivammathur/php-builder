#!/usr/bin/env bash

# Function to update the build log
log_build() {
  gh release download -p "build.log" || true
  date '+%Y.%m.%d' | sudo tee -a build.log
  assets+=("./build.log")
}

get_version_from_branch() {
  curl -sL https://raw.githubusercontent.com/php/php-src/"$1"/main/php_version.h | grep -Po 'PHP_VERSION "\K[0-9]+\.[0-9]+\.[0-9][0-9a-zA-Z-]*' 2>/dev/null || true
}

# Function to update the PHP version log
log_version() {
  assets+=("scripts/install.sh")
  for PHP_VERSION in 8.0 8.1 8.2; do
    new_version=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($PHP_VERSION.[0-9]+)" | head -n 1)
    if [ "$new_version" = "" ]; then
      new_version=$(get_version_from_branch PHP-"$PHP_VERSION")
      if [ "$new_version" = "" ]; then
        new_version=$(get_version_from_branch master)
      fi
    fi
    echo "$new_version" > "php$PHP_VERSION.log"
    assets+=("./php$PHP_VERSION.log")
  done
}

# Exit if commit message has skip-release.
[[ "$GITHUB_MESSAGE" = *skip-release* ]] && exit 0;

# Remove SAPI builds.
rm -rf ./builds/php-sapi*

# Build assets array with builds.
assets=()
for asset in ./builds/*/*; do
  assets+=("$asset")
done

# Update logs.
log_version
log_build

# Create or update release.
if ! gh release view builds; then
  gh release create "builds" "${assets[@]}" -t "builds" -n "builds"
else
  gh release upload "builds" "${assets[@]}" --clobber
fi
