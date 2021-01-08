if [[ "$GITHUB_MESSAGE" != *no-ship* ]]; then
  set -x
  curl -o ./install.sh -sL https://dl.bintray.com/shivammathur/php/php-builder.sh
  assets=()
  for asset in ./builds/*/*; do
    assets+=("$asset")
  done
  assets+=("./install.sh")
  for version in 8.0 8.1; do
    tag=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($version.[0-9]+)" | head -n 1)
    if [ "$tag" = "" ]; then tag='nightly'; fi
    echo "$tag" > "php$version.log"
    assets+=("./php$version.log")
  done
  gh release delete "builds" -y || true
  gh release create "builds" "${assets[@]}" -t "builds" -n "builds"
fi
