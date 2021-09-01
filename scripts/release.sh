#!/usr/bin/env bash

# Function to update the build log
log_build() {
  gh release download -p "build.log" || true
  date '+%Y.%m.%d' | sudo tee -a build.log
  assets+=("./build.log")
}

# Function to update the PHP version log
log_version() {
  assets+=("scripts/install.sh")
  for version in 8.0 8.1 8.2; do
    tag=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($version.[0-9]+)" | head -n 1)
    if [ "x$tag" = "x" ]; then
      tag=$(curl -sL https://github.com/php/php-src/releases.atom | grep -Po -m1 "php-$PHP_VERSION.[0-9]+-?\K(rc|RC)" | head -n 1 | tr '[:upper:]' '[:lower:]')
      if [ "x$tag" = "x" ]; then
        tag='nightly';
      fi
    fi
    echo "$tag" > "php$version.log"
    assets+=("./php$version.log")
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
