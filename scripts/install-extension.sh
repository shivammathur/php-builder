#!/usr/bin/env bash

extension=$1
repo=$2
tag=$3
INSTALL_ROOT=$4
shift 4
params=("$@")

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

if [[ "$repo" != "pecl" && "$tag" = "latest" ]]; then
  tag="$(get_latest_git_tag "$repo")"
fi

# Fetch the extension source.
if [ "$repo" = "pecl" ]; then
  if [ -n "${tag// }" ]; then
    "$INSTALL_ROOT"/usr/bin/pecl download "$extension-$tag"
  else
    "$INSTALL_ROOT"/usr/bin/pecl download "$extension"
  fi
  mv "$extension"*.tgz /tmp/"$extension".tar.gz
else
  curl -o "/tmp/$extension.tar.gz" -sSL "$repo/archive/${tag/\//%2f}.tar.gz"
fi

# Extract it to /tmp and build the extension in INSTALL_ROOT
tar xf "/tmp/$extension.tar.gz" -C /tmp
(
  if [ "$repo" = "pecl" ]; then
    cd /tmp/"$extension"-* || exit 1
  else
    tag=${tag#v}
    cd /tmp/"$(basename "$repo")"-"${tag/\//-}" || exit 1
  fi
  export SED=$(command -v sed)
  patch_"${extension}" 2>/dev/null || true
  phpize
  ./configure "--with-php-config=/usr/bin/php-config" "${params[@]}"
  make -j"$(nproc)"
  make install
  # shellcheck disable=SC2097
  # shellcheck disable=SC2098
  INSTALL_ROOT="$INSTALL_ROOT" make install DESTDIR="$INSTALL_ROOT"
)