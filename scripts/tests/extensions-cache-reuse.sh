#!/usr/bin/env bash
set -euo pipefail

# Exercise a previously published APCu cache against a newly installed PHP and
# the APCu metadata from its new cache: archive metadata is never executed.
: "${1:?old APCu cache archive}" "${2:?fresh APCu metadata}" "${3:?installed php-config}"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=scripts/extensions-cache.sh
source "$repo/scripts/extensions-cache.sh"
archive=$(realpath "$1")
metadata=$(realpath "$2")
cache_php_config=$(command -v "$3")
cache_php=$("$cache_php_config" --php-binary)
cache_ext_dir=$("$cache_php_config" --extension-dir)
cache_core_args=()
declare -A cache_configs=()
cache_work=$(mktemp -d)
trap 'rm -rf "$cache_work"' EXIT

jq -e '.inputs.source.package == "apcu" and .inputs.dependencies == {}' "$metadata" >/dev/null
jq .inputs "$metadata" > "$cache_work/inputs.json"
# Verify that the supplied fresh metadata actually describes this PHP runtime.
jq --argjson abi "$(cache_php_abi "$("$cache_php" -n -i)")" \
  --arg configure "$("$cache_php_config" --configure-options)" \
  '.context.abi = $abi | .context.configure = $configure' "$cache_work/inputs.json" > "$cache_work/runtime-inputs.json"
cache_input_identity "$cache_work/inputs.json" > "$cache_work/expected"
cache_input_identity "$cache_work/runtime-inputs.json" > "$cache_work/actual"
cmp "$cache_work/expected" "$cache_work/actual"

cache_extract "$archive" "$cache_work/restored"
candidate="$cache_work/restored/extensions/apcu"
version=$(jq -er '.inputs.source.version' "$metadata")
cache_reuse apcu "$candidate" "$cache_work/inputs.json" "$version"
printf 'Reused previously published APCu %s with PHP %s\n' "$version" "$("$cache_php" -n -r 'echo PHP_VERSION;')"
sha256sum "$candidate/root/$cache_ext_dir/apcu.so" "$cache_php"

reject() {
  local reason=$1 input=$2 payload=${3:-$candidate}
  if cache_reuse apcu "$payload" "$input" "$version" > "$cache_work/rejection" 2>&1; then
    echo "Unexpected cache hit: $reason" >&2
    exit 1
  fi
  grep -F "$reason" "$cache_work/rejection"
}

for change in '.context.abi["PHP API"] = "incompatible"' \
  '.context.flags.CFLAGS += " -fsanitize=address"' '.source.version = "different"' \
  '.dependencies.other = "different"'; do
  jq "$change" "$cache_work/inputs.json" > "$cache_work/changed-inputs.json"
  reject 'changed ' "$cache_work/changed-inputs.json"
done

cp -a "$candidate" "$cache_work/corrupt"
printf '\ncorrupted\n' >> "$cache_work/corrupt/root/$cache_ext_dir/apcu.so"
reject 'payload checksum or mode mismatch' "$cache_work/inputs.json" "$cache_work/corrupt"

cp -a "$candidate" "$cache_work/mode"
chmod 600 "$cache_work/mode/root/$cache_ext_dir/apcu.so"
reject 'payload checksum or mode mismatch' "$cache_work/inputs.json" "$cache_work/mode"

cp -a "$candidate" "$cache_work/manifest"
printf '\n' >> "$cache_work/manifest/files"
reject 'file manifest checksum mismatch' "$cache_work/inputs.json" "$cache_work/manifest"

cp -a "$candidate" "$cache_work/version"
jq '.runtime_version = "0.0.0"' "$candidate/metadata.json" > "$cache_work/version/metadata.json"
reject 'load, runtime version or smoke check failed' "$cache_work/inputs.json" "$cache_work/version"

# A self-consistent manifest still cannot make an unloadable extension reusable.
cp -a "$candidate" "$cache_work/unloadable"
printf 'not an extension\n' > "$cache_work/unloadable/root/$cache_ext_dir/apcu.so"
cache_inventory "$cache_work/unloadable/root" > "$cache_work/unloadable/files"
jq --arg hash "$(cache_hash "$cache_work/unloadable/files")" '.files_sha256 = $hash' \
  "$candidate/metadata.json" > "$cache_work/unloadable/metadata.json"
reject 'load, runtime version or smoke check failed' "$cache_work/inputs.json" "$cache_work/unloadable"
echo 'Old extension cache reuse and rejection checks passed (10 cases)'
