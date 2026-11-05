#!/usr/bin/env bash

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

  # GitHub can mark an alpha release as non-prerelease, so also check the tag name.
  latest_tag=$(gh api "repos/$repo_slug/releases?per_page=100" \
    --jq '[.[] | select(.draft == false and .prerelease == false and (.tag_name | test("^v?[0-9]+[.][0-9]+[.][0-9]+$"))) | .tag_name] | max_by(ltrimstr("v") | split(".") | map(tonumber)) // empty' \
    2>/dev/null || true)
  if [ -z "$latest_tag" ]; then
    repo_owner="${repo_slug%%/*}"
    repo_name="${repo_slug##*/}"
    # shellcheck disable=SC2016
    graph_query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){refs(refPrefix:"refs/tags/",first:100,orderBy:{field:TAG_COMMIT_DATE,direction:DESC}){nodes{name}}}}'
    latest_tag=$(gh api graphql -f owner="$repo_owner" -f name="$repo_name" -f query="$graph_query" \
      --jq '[.data.repository.refs.nodes[].name | select(test("^v?[0-9]+[.][0-9]+[.][0-9]+$"))] | max_by(ltrimstr("v") | split(".") | map(tonumber)) // empty' \
      2>/dev/null || true)
  fi

  if [ -z "$latest_tag" ]; then
    echo "Could not determine latest stable tag for $repo_url" >&2
    exit 1
  fi

  printf '%s' "$latest_tag"
}

# Resolve once and pass the exact release/commit to both the cache and installer.
resolve_extension_source() {
  local extension=$1 repo=$2 ref=$3 package releases versions version refs commit
  if [ "$repo" = pecl ]; then
    package=$extension
    [ "$extension" != http ] || package=pecl_http
    releases=$(curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 \
      "https://pecl.php.net/rest/r/$package/allreleases.xml") || return 1
    versions=$(awk 'BEGIN { RS="</r>" }
      match($0, /<v>[^<]+<\/v>/) {
        version=substr($0,RSTART+3,RLENGTH-7)
        if (match($0, /<s>[^<]+<\/s>/)) print version, substr($0,RSTART+3,RLENGTH-7)
      }' <<<"$releases")
    if [ -z "$ref" ]; then
      ref=$(awk '$2=="stable" {print $1; exit}' <<<"$versions")
      [ -n "$ref" ] || ref=$(awk 'NR==1 {print $1}' <<<"$versions")
    fi
    if [[ ! "$ref" =~ ^[0-9][A-Za-z0-9.]*$ ]] || ! awk '{print $1}' <<<"$versions" | grep -Fxq "$ref"; then
      echo "Cannot resolve PECL version for $extension: $ref" >&2
      return 1
    fi
    jq -cn --arg repo pecl --arg package "$package" --arg version "$ref" \
      '{repo:$repo, package:$package, version:$version, ref:$version}'
    return
  fi

  [ "$ref" != latest ] || ref=$(get_latest_git_tag "$repo") || return 1
  version=$ref
  if [[ "$ref" =~ ^[a-fA-F0-9]{40}$ ]]; then
    commit=${ref,,}
  else
    refs=$(git ls-remote "$repo" "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}") || return 1
    commit=$(awk -v ref="$ref" '
      $2=="refs/heads/"ref {head=$1}
      $2=="refs/tags/"ref {tag=$1}
      $2=="refs/tags/"ref"^{}" {peeled=$1}
      END {print peeled ? peeled : (tag ? tag : head)}' <<<"$refs")
  fi
  [[ "$commit" =~ ^[a-fA-F0-9]{40}$ ]] || { echo "Cannot resolve $repo at $ref" >&2; return 1; }
  jq -cn --arg repo "$repo" --arg version "$version" --arg ref "$commit" \
    '{repo:$repo, version:$version, ref:$ref}'
}
