# Check that a build of the stable PHP version already exists.
check_stable() {
  # Set release URL
  RELEASE="https://github.com/${GITHUB_REPOSITORY:?}/releases/download/builds"

  # if commit message does not have build-all...
  # then, check if a build of the stable PHP version exists
  # If yes, then fetch it and exit, or continue.
  if [[ "$GITHUB_MESSAGE" != *build-all* ]]; then
    if [ "$new_version" = "$(curl -sL "$RELEASE"/php"$PHP_VERSION".log)" ]; then
      (
        mkdir -p "${INSTALL_ROOT:?}"
        cd "$INSTALL_ROOT"/.. || exit
        curl -sLO "$RELEASE/php_$PHP_VERSION+$ID$VERSION_ID.tar.xz"
        curl -sLO "$RELEASE/php_$PHP_VERSION+$ID$VERSION_ID.tar.zst"
        ls -la
      )
      echo "$new_version" exists
      exit 0
    fi
  fi
}

# Function to get new version from php.net releases and set PHP branch if nightly.
get_version() {
  new_version=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($PHP_VERSION.[0-9]+)" | head -n 1)
  if [ "$new_version" = "" ]; then
    new_version='nightly'
    export branch="$new_version"
  else
    check_stable
  fi
}