#!/usr/bin/env bash

branch=${1:?}
commit_file=${2:?}

ref="$(git ls-remote --exit-code https://github.com/php/php-src "refs/heads/$branch")" || exit 1
commit="${ref%%$'\t'*}"
[[ "$ref" = "$commit"$'\t'"refs/heads/$branch" && "$commit" =~ ^[0-9a-f]{40}$ ]] || exit 1
printf '%s\n' "$commit" > "$commit_file"
