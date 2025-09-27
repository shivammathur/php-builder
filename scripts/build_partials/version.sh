# Check that a build of the stable PHP version already exists.
check_stable() {
  # Set release URL
  RELEASE="https://github.com/${GITHUB_REPOSITORY:?}/releases/download/$PHP_VERSION"

  # if commit message does not have build-all...
  # then, check if a build of the stable PHP version exists
  # If yes, then fetch it and exit, or continue.
  if [[ "$GITHUB_MESSAGE" != *build-all* ]]; then
    if [ "$new_version" = "$(curl -sL "$RELEASE"/php"$PHP_VERSION".log)" ]; then
      (
        mkdir -p "${INSTALL_ROOT:?}"
        cd "$INSTALL_ROOT"/.. || exit
        arch="$(arch)"
        [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && ARCH_SUFFIX='_arm64' || ARCH_SUFFIX=''
        curl -sLO "$RELEASE/php_$PHP_VERSION+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz"
        curl -sLO "$RELEASE/php_$PHP_VERSION+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"
        ls -la
      )
      echo "$new_version" exists
      exit 0
    fi
  fi
}

# Function to get the latest stable release tag for a PHP version.
get_stable_release_tag() {
  source=$1
  if [ "$source" = "--web-php" ]; then
    release_tag="$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-(${PHP_VERSION//./\\.}\.[0-9]+)" | head -n 1)"
    echo "${release_tag:-$(curl -sL https://www.php.net/releases | grep -Po "<h2>\K${PHP_VERSION//./\\.}\.[0-9]+" | head -n1 | sed 's/^/php-/')}"
  else
    curl -H "Authorization: Bearer $GITHUB_TOKEN" -sL "https://api.github.com/repos/php/php-src/git/matching-refs/tags%2Fphp-$PHP_VERSION." | grep -Eo "php-[0-9]+\.[0-9]+\.[0-9]+\"" | sort -V | tail -1 | cut -d '"' -f 1
  fi
}

# Function to get the PHP version from a branch.
get_version_from_branch() {
  curl -sL https://raw.githubusercontent.com/php/php-src/"$1"/main/php_version.h | grep -Po 'PHP_VERSION "\K[0-9]+\.[0-9]+\.[0-9][0-9a-zA-Z-]*' 2>/dev/null || true
}

# Function to get new version from php.net releases and set PHP branch if nightly.
get_version() {
  new_version=$(get_stable_release_tag "$PHP_SOURCE")
  if [ "$new_version" = "" ]; then
    # Since the version is not in stable releases, it has to be nightly or RC
    # Checking if there is a PHP-$PHP_VERSION branch and we can parse the version from it
    # Otherwise for sane inputs, the version should be in master.
    new_version=$(get_version_from_branch PHP-"$PHP_VERSION")
    if [ "$new_version" = "" ]; then
      new_version=$(get_version_from_branch master)
      export branch="master"
    else
      for branch_name in "PHP-$PHP_VERSION" "PHP-$PHP_VERSION.0"; do
        ref="$(git ls-remote --heads https://github.com/php/php-src "$branch_name")"
        if [[ -n "$ref" ]]; then
          export branch=$branch_name
          break;
        fi
      done  
    fi
    export stable="false"
  else
    export branch="$new_version"
    export stable="true"
    # Only run check_stable for stable versions in the feed.
    check_stable
  fi
}