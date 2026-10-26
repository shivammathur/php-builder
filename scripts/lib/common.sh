#!/usr/bin/env bash

library_names() {
  local config_dir=${1:-config/lib}
  local config

  [ -d "$config_dir" ] || return 0
  for config in "$config_dir"/*; do
    [ -f "$config" ] || continue
    basename "$config"
  done
}

library_package_version_from_config() (
  local config=$1
  local LIB_PACKAGE_VERSION=

  # shellcheck source=/dev/null
  . "$config"
  [ -n "$LIB_PACKAGE_VERSION" ] || return 1
  printf '%s\n' "$LIB_PACKAGE_VERSION"
)

library_binary_packages_from_config() (
  local config=$1
  local LIB_BINARY_PACKAGES=()
  local package

  # shellcheck source=/dev/null
  . "$config"
  [ "${#LIB_BINARY_PACKAGES[@]}" -gt 0 ] || return 1
  for package in "${LIB_BINARY_PACKAGES[@]}"; do
    printf '%s\n' "$package"
  done
)

php_needs_pcre3() {
  local php_version=${1:-}

  [ -z "$php_version" ] && return 0
  [[ "$php_version" =~ ^(5\.6|7\.[0-2])($|[^0-9]) ]]
}

library_matches_php_version() {
  local library=$1
  local php_version=${2:-}

  [ -z "$php_version" ] && return 0
  case "$library" in
    pcre2)
      ! php_needs_pcre3 "$php_version"
      ;;
    pcre3)
      php_needs_pcre3 "$php_version"
      ;;
    *)
      return 0
      ;;
  esac
}

library_artifact_version() {
  local package_version=$1
  local dist_id=$2
  local dist_version=$3
  local safe_version

  safe_version=$(printf '%s' "$package_version" | sed -E 's/[^A-Za-z0-9._-]+/./g; s/^[.]+//; s/[.]+$//; s/[.][.]+/./g')
  printf '%s.%s%s' "$safe_version" "$dist_id" "$dist_version"
}

library_artifact_name() {
  local package=$1
  local package_version=$2
  local dist_id=$3
  local dist_version=$4
  local arch=${5:-}

  [ -n "$arch" ] || arch=$(dpkg --print-architecture)

  printf '%s_%s_%s' "$package" "$(library_artifact_version "$package_version" "$dist_id" "$dist_version")" "$arch"
}
