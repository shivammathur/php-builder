#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=scripts/extensions-cache.sh
source "$repo/scripts/extensions-cache.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
checks=0

cat > "$work/base.json" <<'JSON'
{
  "context": {
    "schema": 2, "php_series": "8.1", "platform": "ubuntu26.04", "architecture": "amd64",
    "abi": {"PHP API": "20210902", "PHP Extension": "20210902", "Zend Extension": "420210902",
      "PHP Extension Build": "API20210902,TS", "Zend Extension Build": "API420210902,TS",
      "Thread Safety": "enabled", "Debug Build": "no"},
    "configure": "--enable-zts CFLAGS=-ffile-prefix-map=/__w/php-builder-security/php-builder-security=. -O2",
    "flags": {"CC": null, "CXX": null,
      "CFLAGS": "-g -O2  -ffile-prefix-map=/__w/php-builder-security/php-builder-security=. -std=gnu17",
      "CXXFLAGS": "-O2 -fdebug-prefix-map=/__w/php-builder-security/php-builder-security=.",
      "CPPFLAGS": "-D_FORTIFY_SOURCE=2", "LDFLAGS": "-Wl,-z,relro",
      "EXTRA_CFLAGS": "-Wall", "ICU_CXXFLAGS": "-std=c++17"},
    "compiler": "cc (Ubuntu 15.2.0-16ubuntu1) 15.2.0",
    "overlays": "overlay-hash", "php_patches": "old-patches", "scripts": "old-scripts", "libraries": "old-libraries"
  },
  "source": {"repo": "pecl", "package": "apcu", "ref": "5.1.28", "version": "5.1.28"},
  "args": ["--enable-debug"], "dependencies": {}
}
JSON

compare() {
  local expected=$1 left=$2 right=$3
  cache_input_identity "$left" > "$work/left"
  cache_input_identity "$right" > "$work/right"
  if cmp -s "$work/left" "$work/right"; then
    [ "$expected" = equal ] || { echo 'Unexpected cache identity match' >&2; exit 1; }
  else
    [ "$expected" = different ] || { diff -u "$work/left" "$work/right"; exit 1; }
  fi
  checks=$((checks + 1))
}

for checkout in /__w/php-builder/php-builder /home/runner/work/php-builder/php-builder \
  /home/runner/work/_temp/managed-runner-123/_work/php-builder/php-builder; do
  jq --arg checkout "$checkout" '
    .context.php_patches = "new-patches" | .context.scripts = "new-scripts" | .context.libraries = "new-libraries"
    | .context.development_commit = "new-commit" | .context.development_headers = "new-headers"
    | walk(if type == "string" then gsub("/__w/php-builder-security/php-builder-security"; $checkout) else . end)
    | .context.flags.CFLAGS |= gsub(" +"; " ")
  ' "$work/base.json" > "$work/changed.json"
  compare equal "$work/base.json" "$work/changed.json"
done

# Every compatibility field and effective extension input remains significant.
while IFS= read -r expression; do
  jq "$expression" "$work/base.json" > "$work/changed.json"
  compare different "$work/base.json" "$work/changed.json"
done <<'JQ'
.context.schema = 3
.context.php_series = "8.2"
.context.platform = "ubuntu24.04"
.context.architecture = "arm64"
.context.abi["PHP API"] = "20220829"
.context.abi["PHP Extension"] = "20220829"
.context.abi["Zend Extension"] = "420220829"
.context.abi["PHP Extension Build"] = "API20210902,NTS"
.context.abi["Zend Extension Build"] = "API420210902,NTS"
.context.abi["Thread Safety"] = "disabled"
.context.abi["Debug Build"] = "yes"
.context.compiler = "cc 16"
.context.overlays = "different-overlay"
.context.configure += " --disable-zts"
.context.flags.CC = "clang"
.context.flags.CXX = "clang++"
.context.flags.CFLAGS += " -fsanitize=address"
.context.flags.CXXFLAGS += " -std=c++20"
.context.flags.CPPFLAGS += " -DOTHER=1"
.context.flags.LDFLAGS += " -static"
.context.flags.EXTRA_CFLAGS += " -funsigned-char"
.context.flags.ICU_CXXFLAGS = "-std=c++20"
.context.flags.CFLAGS |= sub("=\\."; "=/different")
.context.flags.CFLAGS |= sub("-ffile-prefix-map"; "-fmacro-prefix-map")
.context.flags.CFLAGS |= sub("/__w/php-builder-security/php-builder-security"; "/usr/include")
.context.flags.CFLAGS |= sub("/__w/php-builder-security/php-builder-security"; "/__w/project/other")
.source.ref = "5.1.29"
.source.version = "5.1.29"
.source.repo = "different-repo"
.source.package = "different-package"
.args += ["--enable-something"]
.dependencies.igbinary = "different-metadata"
JQ

# Preserve arbitrary prefix maps, their order, and significant shell quoting.
for pair in \
  '-ffile-prefix-map=/usr/include=. X|-ffile-prefix-map=/tmp/toolchain=. X' \
  '-O2 -O0|-O0 -O2' \
  "-DMSG='a  b'|-DMSG='a b'" \
  '-DMSG="a  b"|-DMSG="a b"' \
  '-DMSG=a\ b|-DMSG=a b'; do
  jq --arg flags "${pair%%|*}" '.context.flags.CFLAGS = $flags' "$work/base.json" > "$work/quoted-left.json"
  jq --arg flags "${pair#*|}" '.context.flags.CFLAGS = $flags' "$work/base.json" > "$work/quoted-right.json"
  compare different "$work/quoted-left.json" "$work/quoted-right.json"
done

# stdin remains supported for the metadata pipeline in cache_reuse.
cat "$work/base.json" | cache_input_identity > "$work/stdin"
cache_input_identity "$work/base.json" > "$work/file"
cmp "$work/stdin" "$work/file"
echo "Extension cache identity checks passed ($checks cases plus stdin)"
