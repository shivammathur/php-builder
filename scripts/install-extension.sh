#!/usr/bin/env bash

extension=$1
repo=$2
tag=$3
INSTALL_ROOT=$4
shift 4
params=("$@")
pecl_package=$extension
PHP_INSTALL_ROOT="${PHP_INSTALL_ROOT:-$INSTALL_ROOT}"

case "$extension" in
  http)
    pecl_package=pecl_http
    ;;
esac

. scripts/patch-extensions.sh

get_latest_git_tag() {
  local repo_url="$1"
  local repo_slug repo_owner repo_name latest_tag graph_query

  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) is required to resolve latest tags" >&2
    exit 1
  fi

  repo_slug="$(echo "$repo_url" | sed -E 's|^https?://github.com/||; s|^git@github.com:||; s|\.git$||; s|/$||')"
  if [[ -z "$repo_slug" || "$repo_slug" = "$repo_url" || "$repo_slug" != */* ]]; then
    echo "Unsupported repository URL: $repo_url" >&2
    exit 1
  fi

  repo_owner="${repo_slug%%/*}"
  repo_name="${repo_slug##*/}"
  # shellcheck disable=SC2016
  graph_query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){refs(refPrefix:"refs/tags/",first:1,orderBy:{field:TAG_COMMIT_DATE,direction:DESC}){nodes{name}}}}'

  latest_tag=$(gh api graphql -f owner="$repo_owner" -f name="$repo_name" -f query="$graph_query" --jq '.data.repository.refs.nodes[0].name' 2>/dev/null || true)
  if [ -z "$latest_tag" ]; then
    latest_tag=$(gh release list --repo "$repo_slug" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)
  fi

  if [ -z "$latest_tag" ]; then
    echo "Could not determine latest tag for $repo_url" >&2
    exit 1
  fi

  printf '%s' "$latest_tag"
}

download_git_archive() {
  local archive_url encoded_tag output
  output="/tmp/$extension.tar.gz"
  encoded_tag="${tag//\//%2f}"

  for archive_url in "$repo/archive/$encoded_tag.tar.gz" "$repo/archive/refs/tags/$encoded_tag.tar.gz"; do
    rm -f "$output"
    if curl -fsSL --retry 5 --retry-all-errors -o "$output" "$archive_url" && tar -tzf "$output" >/dev/null 2>&1; then
      return 0
    fi
  done

  echo "Could not download a valid archive for $extension from $repo at $tag" >&2
  return 1
}

if [[ "$repo" != "pecl" && "$tag" = "latest" ]]; then
  tag="$(get_latest_git_tag "$repo")" || exit 1
fi

# Clean stale sources from previous local builds of the same extension.
rm -rf /tmp/"$extension"-* /tmp/"$pecl_package"-* /tmp/"$extension".tar.gz "$extension"*.tgz "$pecl_package"*.tgz

# Fetch the extension source.
if [ "$repo" = "pecl" ]; then
  "$PHP_INSTALL_ROOT"/usr/bin/pecl channel-update pecl.php.net || true
  if [ -n "${tag// }" ]; then
    "$PHP_INSTALL_ROOT"/usr/bin/pecl download "$pecl_package-$tag" || compgen -G "$pecl_package*.tgz" >/dev/null || exit 1
  else
    "$PHP_INSTALL_ROOT"/usr/bin/pecl download "$pecl_package" || compgen -G "$pecl_package*.tgz" >/dev/null || exit 1
  fi
  mv "$pecl_package"*.tgz /tmp/"$extension".tar.gz || exit 1
else
  download_git_archive || exit 1
fi

# Extract it to /tmp and build the extension in INSTALL_ROOT
tar xf "/tmp/$extension.tar.gz" -C /tmp || exit 1
(
  if [ "$repo" = "pecl" ]; then
    cd /tmp/"$pecl_package"-* || exit 1
  else
    tag=${tag#v}
    cd /tmp/"$(basename "$repo")"-"${tag/\//-}" || exit 1
  fi
  SED=$(command -v sed) || exit 1
  export SED
  configure_legacy_extension_flags
  if declare -f "patch_${extension}" >/dev/null; then
    "patch_${extension}"
  fi
  phpize || exit 1
  ./configure "--with-php-config=/usr/bin/php-config" "${params[@]}" || exit 1
  make -j"$(nproc)" || exit 1
  make install || exit 1
  # shellcheck disable=SC2097
  # shellcheck disable=SC2098
  INSTALL_ROOT="$INSTALL_ROOT" make install DESTDIR="$INSTALL_ROOT" || exit 1
) || exit 1
