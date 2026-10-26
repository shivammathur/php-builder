#!/usr/bin/env bash
set -e

library_json_array=()

IFS=' ' read -r -a container_os_array <<< "${CONTAINER_OS_LIST:?}"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/../.." && pwd)
config_dir=${LIBRARIES_CONFIG_DIR:-"$repo_dir/config/lib"}
# shellcheck source=scripts/lib/common.sh
. "$script_dir/common.sh"

get_container_base() {
  [[ $1 = arm64v8/* ]] && echo "${CONTAINER_BASE_ARM:?}" || echo "${CONTAINER_BASE:?}"
}

get_arch() {
  [[ $1 = arm64v8/* ]] && echo arm64 || echo amd64
}

get_dist() {
  local container=$1
  local image=${container%:*}

  echo "${image##*/}"
}

get_dist_version() {
  local dist=$1
  local container=$2
  local version=${container##*:}

  case "$dist:$version" in
    debian:trixie)
      echo 13
      ;;
    *)
      echo "$version"
      ;;
  esac
}

for os in "${container_os_array[@]}"; do
  dist="$(get_dist "$os")"
  dist_version="$(get_dist_version "$dist" "$os")"
  os_base="$(get_container_base "$os")"
  arch="$(get_arch "$os")"

  while IFS= read -r library; do
    [ -n "$library" ] || continue
    library_json_array+=("{\"container\": \"$os\", \"container-base\": \"$os_base\", \"dist\": \"$dist\", \"dist-version\": \"$dist_version\", \"arch\": \"$arch\", \"library\": \"$library\"}")
  done < <(library_names "$config_dir")
done

output_file=${GITHUB_OUTPUT:-/dev/stdout}
(
  # shellcheck disable=SC2001
  echo "library_matrix={\"include\":[$(echo "${library_json_array[@]}" | sed -e 's|} {|}, {|g')]}"
) >> "$output_file"
