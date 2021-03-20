log_build() {
  gh release download -p "build.log" || true
  date '+%Y.%m.%d' | sudo tee -a build.log
  assets+=("./build.log")
}

log_version() {
  assets+=("scripts/install.sh")
  for version in 8.0 8.1; do
    tag=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($version.[0-9]+)" | head -n 1)
    if [ "x$tag" = "x" ]; then
      tag='nightly';
    fi
    echo "$tag" > "php$version.log"
    assets+=("./php$version.log")
  done
}

if [[ "$GITHUB_MESSAGE" != *skip-release* ]]; then
  set -x
  assets=()
  for asset in ./builds/*/*; do
    assets+=("$asset")
  done
  log_version
  log_build
  if ! gh release view builds; then
    gh release create "builds" "${assets[@]}" -t "builds" -n "builds"
  else
    gh release upload "builds" "${assets[@]}" --clobber
  fi
fi
