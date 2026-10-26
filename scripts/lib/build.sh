#!/usr/bin/env bash
set -e

print_help() {
  cat << HELP

Usage: ${0} [options]

Build configured Debian library packages for the current Debian/Ubuntu image
and publish the selected binary packages as release assets.

Options:
  --config <path>     Build one library config file
  --config-dir <path> Library config directory. Default: config/lib
  --library <name>    Build one library from config/lib/<name>
  --out-dir <path>    Output directory. Default: /tmp/libraries
  --target <target>   Config target. Default: \$ID-\$VERSION_ID
  --keep-work-dir     Keep the temporary build directory
  -h, --help          Show this help

HELP
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

run_as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

retry_command() {
  bash "$retry_script" 5 10 "$@"
}

git_clone_with_retries() {
  local repo=$1
  local destination=$2

  bash "$retry_script" 5 10 bash -c 'rm -rf "$2"; git clone "$1" "$2"' _ "$repo" "$destination"
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive run_as_root apt-get install -y --no-install-recommends "$@"
}

install_build_tools() {
  run_as_root apt-get update
  apt_install \
    build-essential \
    bzip2 \
    ca-certificates \
    curl \
    devscripts \
    dpkg-dev \
    equivs \
    fakeroot \
    file \
    git \
    xz-utils
}

fetch_upstream_source() {
  local source_name=$1
  local source_parent=$2
  local archive

  mkdir -p "$source_parent"
  source_dir="$source_parent/source"
  rm -rf "$source_dir"

  case "${LIB_UPSTREAM_TYPE:-archive}" in
    archive)
      archive="$source_parent/$(basename "${LIB_UPSTREAM_URL%%\?*}")"
      log "Downloading source: $source_name"
      curl --retry 5 --retry-all-errors -fsSL "$LIB_UPSTREAM_URL" -o "$archive"
      [ -z "${LIB_UPSTREAM_SHA256:-}" ] || printf '%s  %s\n' "$LIB_UPSTREAM_SHA256" "$archive" | sha256sum -c -
      mkdir -p "$source_dir"
      tar -xf "$archive" -C "$source_dir" --strip-components=1
      ;;
    git)
      log "Cloning official upstream source: $source_name"
      git_clone_with_retries "$LIB_UPSTREAM_URL" "$source_dir"
      retry_command git -C "$source_dir" checkout --detach "$LIB_UPSTREAM_REF"
      ;;
    *)
      die "Unsupported type for $source_name: ${LIB_UPSTREAM_TYPE:-}"
      ;;
  esac
}

fetch_packaging_source() {
  local source_name=$1
  local source_parent=$2
  local packaging_dir

  packaging_dir="$source_parent/packaging"
  rm -rf "$packaging_dir"
  log "Cloning packaging metadata: $source_name"
  git_clone_with_retries "$LIB_PACKAGING_URL" "$packaging_dir"
  checkout_packaging_ref "$packaging_dir" "$packaging_ref"
  rm -rf "$source_dir/debian"
  cp -a "$packaging_dir/debian" "$source_dir/debian"
}

checkout_packaging_ref() {
  local packaging_dir=$1
  local ref=$2

  if git -C "$packaging_dir" rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
    retry_command git -C "$packaging_dir" checkout --detach "$ref"
  elif git -C "$packaging_dir" rev-parse --verify --quiet "origin/$ref^{commit}" >/dev/null; then
    retry_command git -C "$packaging_dir" checkout --detach "origin/$ref"
  else
    retry_command git -C "$packaging_dir" fetch origin "$ref"
    retry_command git -C "$packaging_dir" checkout --detach FETCH_HEAD
  fi
}

build_debian_package() {
  local source_name=$1
  local source_parent=$2

  fetch_upstream_source "$source_name" "$source_parent"
  fetch_packaging_source "$source_name" "$source_parent"

  (
    cd "$source_dir"
    for command in "${LIB_PREPARE_COMMANDS[@]}"; do
      eval "$command"
    done
    dpkg-source --before-build .
    mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
    DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-nocheck}" dpkg-buildpackage -us -uc -b -rfakeroot
  )
}

load_library_config() {
  local config=$1

  unset LIB_UPSTREAM_TYPE LIB_UPSTREAM_URL LIB_UPSTREAM_REF LIB_UPSTREAM_SHA256
  unset LIB_PACKAGE_VERSION LIB_PACKAGING_URL LIB_PACKAGING_REF
  unset LIB_REFERENCE_URL LIB_PACKAGING_REFERENCE_URL
  LIB_BINARY_PACKAGES=()
  LIB_PACKAGING_REFS=()
  LIB_PREPARE_COMMANDS=()
  # shellcheck source=/dev/null
  . "$config"

  LIB_UPSTREAM_TYPE=${LIB_UPSTREAM_TYPE:-archive}
  [ -n "${LIB_UPSTREAM_URL:-}" ] || die "Missing LIB_UPSTREAM_URL in $config"
  [ -n "${LIB_UPSTREAM_REF:-}" ] || die "Missing LIB_UPSTREAM_REF in $config"
  [ -n "${LIB_PACKAGE_VERSION:-}" ] || die "Missing LIB_PACKAGE_VERSION in $config"
  dpkg --validate-version "$LIB_PACKAGE_VERSION" || die "Invalid LIB_PACKAGE_VERSION in $config: $LIB_PACKAGE_VERSION"
  [ -n "${LIB_PACKAGING_URL:-}" ] || die "Missing LIB_PACKAGING_URL in $config"
  [ -n "${LIB_PACKAGING_REF:-}" ] || die "Missing LIB_PACKAGING_REF in $config"
  [ -n "${LIB_REFERENCE_URL:-}" ] || die "Missing LIB_REFERENCE_URL in $config"
  [ -n "${LIB_PACKAGING_REFERENCE_URL:-}" ] || die "Missing LIB_PACKAGING_REFERENCE_URL in $config"
  [ "${#LIB_BINARY_PACKAGES[@]}" -gt 0 ] || die "Missing LIB_BINARY_PACKAGES in $config"
}

select_packaging_ref() {
  local target_ref

  packaging_ref=$LIB_PACKAGING_REF
  for target_ref in "${LIB_PACKAGING_REFS[@]}"; do
    if [ "${target_ref%%=*}" = "$target" ]; then
      packaging_ref=${target_ref#*=}
    fi
  done
}

publish_binary_packages() {
  local package deb version artifact

  for package in "${LIB_BINARY_PACKAGES[@]}"; do
    deb=$(find "$source_parent" -maxdepth 1 -type f -name "$package"'_*.deb' | sort | head -n 1)
    [ -n "$deb" ] || die "Built package not found: $package from $source_name"
    # shellcheck disable=SC2016
    version=$(dpkg-deb -W --showformat='${Version}' "$deb")
    dpkg --compare-versions "$version" eq "$LIB_PACKAGE_VERSION" \
      || die "$source_name built version $version does not match configured version $LIB_PACKAGE_VERSION"
    artifact=$(library_artifact_name "$package" "$LIB_PACKAGE_VERSION" "$ID" "$VERSION_ID")
    log "Publishing $package=$version as $artifact.deb"
    cp -f "$deb" "$publish_dir/$artifact.deb"
  done
}

publish_provenance() {
  local source_artifact buildinfo

  source_artifact=$(library_artifact_name "$source_name" "$LIB_PACKAGE_VERSION" "$ID" "$VERSION_ID")
  buildinfo=$(find "$source_parent" -maxdepth 1 -type f -name '*.buildinfo' | sort | head -n 1)
  [ -n "$buildinfo" ] || die "Buildinfo not found for $source_name"
  cp -f "$buildinfo" "$publish_dir/$source_artifact.buildinfo"
}

config_file=
config_dir=
library=
out_dir=${OUT_DIR:-/tmp/libraries}
target=
keep_work_dir=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      config_file=$2
      shift 2
      ;;
    --config-dir)
      config_dir=$2
      shift 2
      ;;
    --library)
      library=$2
      shift 2
      ;;
    --out-dir)
      out_dir=$2
      shift 2
      ;;
    --target)
      target=$2
      shift 2
      ;;
    --keep-work-dir)
      keep_work_dir=true
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/../.." && pwd)
retry_script="$repo_dir/scripts/retry.sh"
# shellcheck source=scripts/lib/common.sh
. "$script_dir/common.sh"

# shellcheck source=/dev/null
. /etc/os-release
[[ "$ID" =~ ^(ubuntu|debian)$ ]] || die "Library builds currently support Debian/Ubuntu only"

config_dir=${config_dir:-"$repo_dir/config/lib"}
target=${target:-"$ID-$VERSION_ID"}

if [ -n "$config_file" ] && [ -n "$library" ]; then
  die "Use either --config or --library, not both"
fi

if [ -n "$library" ]; then
  config_file="$config_dir/$library"
fi

if [ -n "$config_file" ]; then
  [ -f "$config_file" ] || die "Missing library config: $config_file"
  config_files=("$config_file")
else
  [ -d "$config_dir" ] || die "Missing library config directory: $config_dir"
  config_files=()
  while IFS= read -r library; do
    [ -n "$library" ] || continue
    [ -f "$config_dir/$library" ] || die "Missing library config: $config_dir/$library"
    config_files+=("$config_dir/$library")
  done < <(library_names "$config_dir")
  [ "${#config_files[@]}" -gt 0 ] || die "No library configs found in: $config_dir"
fi

work_dir=$(mktemp -d)
source_root="$work_dir/sources"
mkdir -p "$source_root"

if [ "$keep_work_dir" = "false" ]; then
  trap 'rm -rf "$work_dir"' EXIT
else
  trap 'printf "Keeping work dir: %s\n" "$work_dir"' EXIT
fi

mkdir -p "$out_dir"

install_build_tools

built_any=false
for config_file in "${config_files[@]}"; do
  source_name=$(basename "$config_file")
  load_library_config "$config_file"
  select_packaging_ref
  source_parent="$source_root/$source_name"
  publish_dir="$work_dir/publish/$source_name"
  rm -rf "$publish_dir"
  mkdir -p "$publish_dir"
  build_debian_package "$source_name" "$source_parent"
  publish_binary_packages
  publish_provenance
  cp -f "$publish_dir"/* "$out_dir"/
  built_any=true
done

[ "$built_any" = "true" ] || die "No library configs found in: $config_dir"
