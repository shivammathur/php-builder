#!/usr/bin/env bash
set -e

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

print_help() {
  cat << HELP

Usage: ${0} [options]

Install configured library releases for the current Debian/Ubuntu target.

Options:
  --config-dir <path> Library config directory. Default: config/lib
  --library <name>    Install one library from config/lib/<name>
  --manifest <path>   Write extracted overlay paths to a manifest
  --php-version <ver> Select PHP-version-specific library overlays
  --root <path>       Extract into this root instead of /
  -h, --help          Show this help

HELP
}

run_as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

configured_libraries() {
  local config_dir=$1
  local requested_library=${2:-}
  local library

  if [ -n "$requested_library" ]; then
    [ -f "$config_dir/$requested_library" ] || return 1
    printf '%s\n' "$requested_library"
    return 0
  fi

  while IFS= read -r library; do
    [ -n "$library" ] || continue
    [ -f "$config_dir/$library" ] || continue
    printf '%s\n' "$library"
  done < <(library_names "$config_dir")
}

extract_deb() {
  local file=$1
  local root=$2

  run_as_root dpkg-deb -x "$file" "$root"
}

record_deb_manifest() {
  local file=$1

  [ -n "$manifest_path" ] || return 0
  dpkg-deb --fsys-tarfile "$file" | tar tf - | sed -E 's#^\./##; /^$/d; /^\.$/d' >> "$manifest_path"
}

download_library_artifact() {
  local url=$1
  local download_path=$2

  if [ ! -s "$download_path" ] || [ "${LIBRARIES_REFRESH:-}" = "1" ]; then
    log "Downloading library release: $(basename "$download_path")"
    run_as_root curl --retry 5 --retry-all-errors -fsSL "$url" -o "$download_path"
  fi
}

install_root=/
config_dir=
library=
manifest_path=
php_version=${PHP_VERSION:-}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config-dir)
      config_dir=$2
      shift 2
      ;;
    --library)
      library=$2
      shift 2
      ;;
    --manifest)
      manifest_path=$2
      shift 2
      ;;
    --php-version)
      php_version=$2
      shift 2
      ;;
    --root)
      install_root=$2
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# shellcheck source=/dev/null
. /etc/os-release

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/../.." && pwd)
# shellcheck source=scripts/lib/common.sh
. "$script_dir/common.sh"
config_dir=${config_dir:-${LIBRARIES_CONFIG_DIR:-"$repo_dir/config/lib"}}

if [ -n "${LIBRARIES_LIBRARY:-}" ] && [ -z "$library" ]; then
  library=$LIBRARIES_LIBRARY
fi

tag=${LIBRARIES_TAG:-libraries}
base_url=${LIBRARIES_BASE_URL:-https://github.com/shivammathur/php-builder/releases/download/$tag}
download_dir=${LIBRARIES_DOWNLOAD_DIR:-/tmp/libraries}

run_as_root mkdir -p "$download_dir"
run_as_root mkdir -p "$install_root"
if [ -n "$manifest_path" ]; then
  mkdir -p "$(dirname "$manifest_path")"
  : > "$manifest_path"
fi

libraries=()
while IFS= read -r configured_library; do
  [ -n "$configured_library" ] || continue
  if [ -z "$library" ] && ! library_matches_php_version "$configured_library" "$php_version"; then
    log "Skipping $configured_library for PHP $php_version"
    continue
  fi
  libraries+=("$configured_library")
done < <(configured_libraries "$config_dir" "$library")
[ "${#libraries[@]}" -gt 0 ] || {
  log "No library release configured in $config_dir"
  exit 0
}

for library in "${libraries[@]}"; do
  package_version=$(library_package_version_from_config "$config_dir/$library")
  while IFS= read -r package; do
    [ -n "$package" ] || continue
    artifact="$(library_artifact_name "$package" "$package_version" "$ID" "$VERSION_ID").deb"
    url="$base_url/$artifact"
    download_path="$download_dir/$artifact"
    download_library_artifact "$url" "$download_path"

    log "Installing library release into $install_root: $artifact"
    extract_deb "$download_path" "$install_root"
    record_deb_manifest "$download_path"
  done < <(library_binary_packages_from_config "$config_dir/$library")
done

if [ "$install_root" = "/" ]; then
  run_as_root ldconfig
fi
