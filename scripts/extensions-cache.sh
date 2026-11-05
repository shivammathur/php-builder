#!/usr/bin/env bash

cache_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/extension-source.sh
. "$cache_repo/scripts/extension-source.sh"

cache_hash() {
  sha256sum < "$1" | cut -d ' ' -f 1
}

cache_relative_path() {
  case "$1" in
    ''|/*|*/../*|../*|*/..|..|./*|*/./*|*/.|.|*//*|*$'\t'*|*$'\r'*|*$'\n'*|*\\*) return 1 ;;
  esac
}

# A sorted inventory covers the entire installation payload, including headers,
# modes and symlinks. Metadata is data only; never source it as shell code.
cache_inventory() (
  local root=$1 file relative mode value
  [ -d "$root" ] || exit 0
  root=$(cd "$root" && pwd -P) || exit 1
  cd "$root" || exit 1
  find . ! -type d -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' file; do
    relative=${file#./}
    cache_relative_path "$relative" || exit 1
    if [ -L "$file" ]; then
      value=$(readlink "$file") || exit 1
      case "$value" in /*|*$'\t'*|*$'\r'*|*$'\n'*|*\\*) exit 1 ;; esac
      case "$(realpath "$file")" in "$root"/*) ;; *) exit 1 ;; esac
      printf 'l\t0\t%s\t%s\n' "$value" "$relative"
    elif [ -f "$file" ]; then
      mode=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file") || exit 1
      [[ "$mode" =~ ^[0-7]{1,3}$ ]] || exit 1
      value=$(cache_hash "$file") || exit 1
      printf 'f\t%s\t%s\t%s\n' "$mode" "$value" "$relative"
    else
      exit 1
    fi
  done
)

# Links travel as manifest entries. The tar contains only regular files and
# directories, so extraction cannot follow archive-supplied links outside staging.
cache_extract() (
  local archive=$1 root=$2 raw name
  raw=$(mktemp) || exit 1
  trap 'rm -f "$raw" "$raw.names" "$raw.types"' EXIT
  zstd -dc "$archive" > "$raw" || exit 1
  tar -tf "$raw" --quoting-style=escape > "$raw.names" || exit 1
  tar -tvf "$raw" --numeric-owner --quoting-style=escape > "$raw.types" || exit 1
  [ -s "$raw.names" ] || exit 1
  while IFS= read -r name; do
    name=${name%/}
    cache_relative_path "$name" || exit 1
    case "$name" in extensions|extensions/*) ;; *) exit 1 ;; esac
  done < "$raw.names"
  awk 'substr($0,1,1)!="-" && substr($0,1,1)!="d" {exit 1}' "$raw.types" || exit 1
  [ -z "$(LC_ALL=C sort "$raw.names" | uniq -d)" ] || exit 1
  mkdir -p "$root" || exit 1
  tar -xf "$raw" -C "$root" --no-same-owner --no-same-permissions
)

cache_archive() (
  local root=$1 archive=$2
  cd "$root" || exit 1
  # Expand hard links into files too; a restored cache is independent of inodes.
  find extensions \( -type f -o -type d \) -print0 | LC_ALL=C sort -z \
    | tar --format=gnu --hard-dereference --no-recursion --null -T - -cf - \
    | zstd -q -10 -T0 -f -o "$archive.partial" || exit 1
  mv "$archive.partial" "$archive"
)

cache_restore_links() {
  local root=$1 manifest=$2 kind mode value relative extra resolved progress index
  local -a links=() targets=() remaining=() pending=()
  root=$(cd "$root" && pwd -P) || return 1
  while IFS=$'\t' read -r kind mode value relative extra; do
    [ -z "$extra" ] && cache_relative_path "$relative" || return 1
    case "$kind" in
      f) [[ "$mode" =~ ^[0-7]{1,3}$ && "$value" =~ ^[a-f0-9]{64}$ ]] || return 1 ;;
      l)
        [ "$mode" = 0 ] || return 1
        case "$value" in ''|/*|*$'\t'*|*$'\r'*|*$'\n'*|*\\*) return 1 ;; esac
        links+=("$relative")
        targets+=("$value")
        ;;
      *) return 1 ;;
    esac
  done < "$manifest"
  # Resolve link chains only after their targets exist, without following unsafe
  # parent directories. A dangling link or cycle makes the candidate a cache miss.
  remaining=("${!links[@]}")
  while [ "${#remaining[@]}" -gt 0 ]; do
    progress=0
    pending=()
    for index in "${remaining[@]}"; do
      relative=${links[$index]}
      value=${targets[$index]}
      resolved=$(realpath "$root/$(dirname "$relative")") || return 1
      case "$resolved/" in "$root/"*) ;; *) return 1 ;; esac
      if resolved=$(realpath "$root/$(dirname "$relative")/$value" 2>/dev/null) && [ -e "$resolved" ]; then
        case "$resolved" in "$root"/*) ;; *) return 1 ;; esac
        ln -s "$value" "$root/$relative" || return 1
        progress=1
      else
        pending+=("$index")
      fi
    done
    [ "$progress" = 1 ] || return 1
    remaining=("${pending[@]}")
  done
}

cache_install_payload() {
  local root=$1 destination=$2 manifest=$3 kind mode value relative target
  while IFS=$'\t' read -r kind mode value relative; do
    target="$destination/$relative"
    mkdir -p "$(dirname "$target")" || return 1
    if [ -L "$target" ] || { [ "$kind" = l ] && [ -e "$target" ]; }; then
      rm -f "$target" || return 1
    fi
    if [ "$kind" = l ]; then
      ln -s "$value" "$target" || return 1
    else
      cp -p "$root/$relative" "$target" || return 1
    fi
  done < "$manifest"
}

cache_read_config() {
  local config=$1 line name
  cache_names=()
  declare -gA cache_configs=() cache_states=()
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r -a cache_parts <<<"$line"
    name=${cache_parts[1]%-*}
    [[ "$name" =~ ^[a-zA-Z0-9_]+$ && -z "${cache_configs[$name]+set}" ]] || return 1
    cache_names+=("$name")
    cache_configs[$name]=$line
  done < "$config"
  [ "${#cache_names[@]}" -gt 0 ]
}

cache_parse_config() {
  local name=$1 type
  read -r -a cache_parts <<<"${cache_configs[$name]}"
  type=${cache_parts[0]}
  if [ "$type" = pecl ]; then
    cache_source_repo=pecl
    cache_source_ref=
    [[ "${cache_parts[1]}" != *-* ]] || cache_source_ref=${cache_parts[1]##*-}
    cache_args=("${cache_parts[@]:2}")
  elif [ "$type" = git ]; then
    cache_source_repo=${cache_parts[2]}
    cache_source_ref=${cache_parts[3]}
    cache_args=("${cache_parts[@]:4}")
  else
    echo "Unknown extension source: $type" >&2
    return 1
  fi
  cache_args+=(--enable-debug)
}

cache_dependencies() {
  local dependency
  local -a dependencies=()
  case "$1" in
    redis|memcached) dependencies=(igbinary msgpack) ;;
    http) dependencies=(raphf propro) ;;
    pq) dependencies=(raphf) ;;
    phalcon) dependencies=(psr) ;;
  esac
  for dependency in "${dependencies[@]}"; do
    [ -z "${cache_configs[$dependency]+set}" ] || printf '%s\n' "$dependency"
  done
}

cache_visit() {
  local name=$1 dependency
  case "${cache_states[$name]:-}" in
    done) return 0 ;;
    visiting) echo "Extension dependency cycle at $name" >&2; return 1 ;;
  esac
  cache_states[$name]=visiting
  while IFS= read -r dependency; do
    cache_visit "$dependency" || return 1
  done < <(cache_dependencies "$name")
  cache_states[$name]='done'
  cache_order+=("$name")
}

cache_php_abi() {
  local info=$1 key value abi='{}'
  for key in 'PHP API' 'PHP Extension' 'Zend Extension' 'PHP Extension Build' 'Zend Extension Build' 'Thread Safety' 'Debug Build'; do
    value=$(awk -F ' => ' -v key="$key" '$1==key {print $2; exit}' <<<"$info")
    [ -n "$value" ] || { echo "Missing PHP ABI field: $key" >&2; return 1; }
    abi=$(jq -c --arg key "$key" --arg value "$value" '. + {($key):$value}' <<<"$abi") || return 1
  done
  printf '%s\n' "$abi"
}

cache_context() {
  local info version abi configure libraries overlays scripts patches compiler flags file
  local -a compiler_command=()
  info=$("$cache_php" -n -i)
  version=$("$cache_php" -n -r 'echo PHP_VERSION;')
  [[ "$version" = "$PHP_VERSION."* ]] || { echo 'Wrong PHP version' >&2; return 1; }
  abi=$(cache_php_abi "$info")
  [ "$("$cache_php_config" --phpapi)" = "$(jq -r '."PHP Extension"' <<<"$abi")" ] || return 1
  if [ "$BUILD" = zts ]; then
    [ "$(jq -r '."Thread Safety"' <<<"$abi")" = enabled ] || return 1
  else
    [ "$BUILD" = nts ] && [ "$(jq -r '."Thread Safety"' <<<"$abi")" = disabled ] || return 1
  fi
  configure=$("$cache_php_config" --configure-options)
  # Record installed packages for provenance. Package updates alone do not
  # invalidate every extension; loading and smoke checks verify shared libraries.
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' \
    | awk '/^(lib|gcc|g\+\+|clang|binutils)|^[^\t]*-dev[\t:]/' | LC_ALL=C sort > "$cache_work/libraries"
  libraries=$(cache_hash "$cache_work/libraries")
  cache_inventory /tmp/libraries > "$cache_work/overlays"
  overlays=$(cache_hash "$cache_work/overlays")
  : > "$cache_work/scripts"
  # Record build recipes for provenance. Scripts can change for other build modes
  # or extensions without affecting this binary's effective inputs.
  for file in scripts/build.sh scripts/install-extension.sh scripts/patch-extensions.sh; do
    printf '%s %s\n' "$(cache_hash "$cache_repo/$file")" "$file" >> "$cache_work/scripts"
  done
  scripts=$(cache_hash "$cache_work/scripts")
  cache_inventory "$cache_repo/config/patches/$PHP_VERSION" > "$cache_work/patches"
  patches=$(cache_hash "$cache_work/patches")
  read -r -a compiler_command <<<"${CC:-cc}"
  compiler=$("${compiler_command[@]}" --version | sed -n '1p')
  flags=$(jq -cn 'env | {CC,CXX,CFLAGS,CPPFLAGS,CXXFLAGS,LDFLAGS,EXTRA_CFLAGS,ICU_CXXFLAGS}')
  jq -S -n --argjson abi "$abi" --argjson flags "$flags" --arg php_series "$PHP_VERSION" \
    --arg platform "$cache_platform" --arg architecture "$cache_arch" --arg configure "$configure" \
    --arg libraries "$libraries" --arg overlays "$overlays" --arg scripts "$scripts" --arg patches "$patches" \
    --arg compiler "$compiler" \
    '{schema:2,php_series:$php_series,abi:$abi,platform:$platform,architecture:$architecture,
      configure:$configure,flags:$flags,compiler:$compiler,libraries:$libraries,overlays:$overlays,
      scripts:$scripts,php_patches:$patches}'
}

cache_input_identity() {
  # PHP compatibility is its version series and PHP/Zend APIs, including the
  # thread/debug build IDs. Accept existing archives with development provenance
  # fields too, so changing this policy does not itself rebuild every extension.
  # Script hashes are provenance: compare effective build flags and extension
  # inputs instead of rejecting normal builds for ASAN-only script changes.
  # Keep configured library overlays in the identity: they may be linked statically.
  jq -S 'del(.context.development_commit, .context.development_headers, .context.libraries, .context.scripts)' "${1:--}"
}

cache_miss() {
  printf 'Cache miss for %s: %s\n' "$1" "$2" >&2
}

cache_input_changes() {
  jq -nr --slurpfile previous "$1" --slurpfile current "$2" '
    [($previous[0] | paths(scalars)), ($current[0] | paths(scalars))] | unique
    | map(. as $path | select(($previous[0] | getpath($path)) != ($current[0] | getpath($path))))
    | map(map(tostring) | join(".")) | join(", ") | if length == 0 then "inputs" else . end'
}

cache_core_options() {
  local builtins ini name priority module
  cache_core_args=()
  builtins=$("$cache_php" -n -m | tr '[:upper:]' '[:lower:]')
  : > "$cache_work/core-modules"
  for ini in "$cache_php_root/etc/php/$PHP_VERSION/mods-available/"*.ini; do
    [ -f "$ini" ] || continue
    module=$(sed -nE 's/^[[:space:]]*extension[[:space:]]*=[[:space:]]*"?([^";[:space:]]+).*/\1/p' "$ini")
    [ -n "$module" ] || continue
    name=${module##*/}
    name=${name%.so}
    [ -z "${cache_configs[$name]+set}" ] && [ -f "$cache_ext_dir/$name.so" ] || continue
    ! grep -Fxqi "$name" <<<"$builtins" || continue
    priority=$(sed -nE 's/.*priority[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$ini")
    printf '%s %s\n' "${priority:-20}" "$name" >> "$cache_work/core-modules"
  done
  while read -r priority name; do
    cache_core_args+=(-d "extension=$cache_ext_dir/$name.so")
  done < <(LC_ALL=C sort -k1,1n -k2 "$cache_work/core-modules")
}

cache_smoke() {
  local name=$1 payload=$2 expected=${3:-} pecl_version=${4:-} dependency directive=extension version output
  local -a options=(-n -d display_errors=stderr -d display_startup_errors=1 -d error_reporting=24575 -d apc.enable_cli=1)
  options+=("${cache_core_args[@]}")
  while IFS= read -r dependency; do
    options+=(-d "extension=$cache_ext_dir/$dependency.so")
  done < <(cache_dependencies "$name")
  [ "$name" != xdebug ] || directive=zend_extension
  options+=(-d "$directive=$payload/$cache_ext_dir/$name.so")
  if ! timeout -k 5 30 "$cache_php" "${options[@]}" "$cache_repo/scripts/smoke-extension.php" "$name" \
      > "$cache_work/smoke.out" 2> "$cache_work/smoke.err"; then
    cat "$cache_work/smoke.out" "$cache_work/smoke.err" >&2
    return 1
  fi
  output=$(cat "$cache_work/smoke.out")
  if [ -s "$cache_work/smoke.err" ] || [[ "$output" != CACHE_SMOKE_OK:* || "$output" = *$'\n'* ]]; then
    cat "$cache_work/smoke.out" "$cache_work/smoke.err" >&2
    return 1
  fi
  version=${output#CACHE_SMOKE_OK:}
  [ -n "$version" ] && { [ -z "$expected" ] || [ "$version" = "$expected" ]; } || return 1
  if [ -n "$pecl_version" ] && [ "${version,,}" != "${pecl_version,,}" ]; then
    echo "$name reports $version, expected PECL $pecl_version" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

cache_reuse() {
  local name=$1 candidate=$2 inputs=$3 pecl_version=$4 expected checksum
  [ -f "$candidate/metadata.json" ] && [ -s "$candidate/files" ] && [ -d "$candidate/root" ] \
    || { cache_miss "$name" 'payload or metadata missing'; return 1; }
  jq -e '.inputs|type=="object"' "$candidate/metadata.json" >/dev/null \
    || { cache_miss "$name" 'invalid input metadata'; return 1; }
  jq '.inputs' "$candidate/metadata.json" | cache_input_identity > "$cache_work/cached-inputs" || return 1
  cache_input_identity "$inputs" > "$cache_work/current-inputs" || return 1
  cmp -s "$cache_work/current-inputs" "$cache_work/cached-inputs" \
    || { cache_miss "$name" "changed $(cache_input_changes "$cache_work/cached-inputs" "$cache_work/current-inputs")"; return 1; }
  checksum=$(jq -er '.files_sha256|strings' "$candidate/metadata.json") \
    || { cache_miss "$name" 'missing manifest checksum'; return 1; }
  [ "$checksum" = "$(cache_hash "$candidate/files")" ] \
    || { cache_miss "$name" 'file manifest checksum mismatch'; return 1; }
  expected=$(jq -er '.runtime_version|strings|select(length>0)' "$candidate/metadata.json") \
    || { cache_miss "$name" 'missing runtime version'; return 1; }
  cache_restore_links "$candidate/root" "$candidate/files" \
    || { cache_miss "$name" 'invalid payload links'; return 1; }
  cache_inventory "$candidate/root" > "$cache_work/cached-files" \
    || { cache_miss "$name" 'invalid payload files'; return 1; }
  cmp -s "$candidate/files" "$cache_work/cached-files" \
    || { cache_miss "$name" 'payload checksum or mode mismatch'; return 1; }
  cache_smoke "$name" "$candidate/root" "$expected" "$pecl_version" >/dev/null \
    || { cache_miss "$name" 'load, runtime version or smoke check failed'; return 1; }
}

cache_build_extension() {
  local name=$1 source repo ref version pecl_version='' dependency dependency_hashes='{}' args_json runtime candidate target
  cache_parse_config "$name"
  source=$(resolve_extension_source "$name" "$cache_source_repo" "$cache_source_ref")
  repo=$(jq -er .repo <<<"$source")
  ref=$(jq -er .ref <<<"$source")
  version=$(jq -er .version <<<"$source")
  [ "$repo" != pecl ] || pecl_version=$version
  while IFS= read -r dependency; do
    dependency_hashes=$(jq -c --arg name "$dependency" --arg hash "$(cache_hash "$cache_work/fresh/extensions/$dependency/metadata.json")" \
      '. + {($name):$hash}' <<<"$dependency_hashes")
  done < <(cache_dependencies "$name")
  args_json=$(jq -cn '$ARGS.positional' --args -- "${cache_args[@]}")
  jq -S -n --slurpfile context "$cache_work/context.json" --argjson source "$source" \
    --argjson args "$args_json" --argjson dependencies "$dependency_hashes" \
    '{context:$context[0],source:$source,args:$args,dependencies:$dependencies}' > "$cache_work/inputs.json"
  candidate="$cache_work/restored/extensions/$name"
  target="$cache_work/fresh/extensions/$name"
  echo "::group::$name"
  if cache_reuse "$name" "$candidate" "$cache_work/inputs.json" "$pecl_version"; then
    mkdir -p "$(dirname "$target")"
    cp -a "$candidate" "$target"
    echo "Reusing $name $version"
  else
    echo "Building $name $version (missing, changed or failed cache candidate)"
    mkdir -p "$target/root"
    bash "$cache_repo/scripts/retry.sh" 5 5 bash "$cache_repo/scripts/install-extension.sh" \
      "$name" "$repo" "$ref" "$target/root" "${cache_args[@]}"
    runtime=$(cache_smoke "$name" "$target/root" '' "$pecl_version")
    cache_inventory "$target/root" > "$target/files"
    jq -S -n --slurpfile inputs "$cache_work/inputs.json" --arg runtime_version "$runtime" \
      --arg files_sha256 "$(cache_hash "$target/files")" \
      '{inputs:$inputs[0],runtime_version:$runtime_version,files_sha256:$files_sha256}' > "$target/metadata.json"
  fi
  cache_install_payload "$target/root" "$cache_root" "$target/files"
  cache_install_payload "$target/root" / "$target/files"
  echo '::endgroup::'
}

cache_main() (
  local name suffix='' arch_suffix='' asset output=/tmp
  cache_root='' cache_php_root='' cache_php='' cache_php_config='' cache_platform=''
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) cache_root=$2 ;;
      --php-root) cache_php_root=$2 ;;
      --php) cache_php=$2 ;;
      --php-config) cache_php_config=$2 ;;
      --platform) cache_platform=$2 ;;
      --output) output=$2 ;;
      *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift 2
  done
  : "${cache_root:?}" "${cache_php_root:?}" "${cache_php:?}" "${cache_php_config:?}" "${cache_platform:?}" "${PHP_VERSION:?}" "${BUILD:?}"
  cd "$cache_repo"
  cache_work=$(mktemp -d /tmp/php-extension-cache.XXXXXXXX)
  trap 'rm -rf "$cache_work"' EXIT
  mkdir -p "$cache_work/restored" "$cache_work/fresh" "$output"
  cache_read_config "config/extensions/$PHP_VERSION"
  cache_order=()
  for name in "${cache_names[@]}"; do cache_visit "$name"; done
  cache_arch=$(dpkg --print-architecture)
  case "$cache_arch" in amd64) ;; arm64) arch_suffix=_arm64 ;; *) echo 'Unsupported architecture' >&2; exit 1 ;; esac
  [ "$BUILD" != zts ] || suffix=-zts
  [ "${ASAN:-}" != asan ] || suffix="${suffix}-asan"
  asset="php_$PHP_VERSION$suffix-extensions-cache+$cache_platform$arch_suffix.tar.zst"
  cache_context > "$cache_work/context.json"
  cache_ext_dir=$("$cache_php_config" --extension-dir)
  cache_core_options
  # Initialize bundled modules before testing custom extensions. Net-SNMP, for
  # example, logs the creation of its runtime directories on the first startup.
  # PHP 5/7 return status 254 for an empty -r program, so exit explicitly.
  timeout -k 5 30 "$cache_php" -n "${cache_core_args[@]}" -r 'exit(0);'
  if [ "${EXTENSIONS_CACHE_REFRESH:-false}" != true ]; then
    if ! timeout -k 5 180 gh release download "$PHP_VERSION" --repo "${GITHUB_REPOSITORY:?}" \
        --pattern "$asset" --dir "$cache_work" || ! cache_extract "$cache_work/$asset" "$cache_work/restored"; then
      echo 'Extension cache unavailable; building as needed'
      rm -rf "$cache_work/restored"
      mkdir -p "$cache_work/restored"
    fi
  fi
  for name in "${cache_order[@]}"; do cache_build_extension "$name"; done
  cache_archive "$cache_work/fresh" "$output/$asset"
  echo "Saved complete extension cache: $output/$asset"
)

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  set -euo pipefail
  cache_main "$@"
fi
