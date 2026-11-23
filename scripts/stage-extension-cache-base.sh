#!/usr/bin/env bash
set -euo pipefail

: "${PHP_VERSION:?}" "${BUILD:?}" "${GITHUB_REPOSITORY:?}"
. /etc/os-release

suffix=''
arch_suffix=''
[ "$BUILD" != zts ] || suffix=-zts
[[ "$(arch)" != aarch64 && "$(arch)" != arm64 ]] || arch_suffix=_arm64
SOURCE_ARTIFACT_DIR=/tmp/cache-source-artifacts
SOURCE_DEBUG_ROOT=/tmp/source-debug
EXTENSIONS_TO_BUILD=$(awk '{split($2,name,"-"); printf "%s ",name[1]}' "config/extensions/$PHP_VERSION")
export SOURCE_ARTIFACT_DIR SOURCE_DEBUG_ROOT EXTENSIONS_TO_BUILD
mkdir -p "$SOURCE_ARTIFACT_DIR"
package="php_$PHP_VERSION$suffix+$ID$VERSION_ID$arch_suffix.tar.zst"
gh release download "$PHP_VERSION" --repo "$GITHUB_REPOSITORY" --dir "$SOURCE_ARTIFACT_DIR" --pattern "$package"
if [ "${EXTENSIONS_CACHE_ONLY:-false}" = true ]; then
  mkdir -p "/tmp/debian/php$PHP_VERSION"
  tar -I zstd -xf "$SOURCE_ARTIFACT_DIR/$package" -C "/tmp/debian/php$PHP_VERSION"
  tar -I zstd -xf "$SOURCE_ARTIFACT_DIR/$package" -C / --no-same-owner
else
  gh release download "$PHP_VERSION" --repo "$GITHUB_REPOSITORY" --dir "$SOURCE_ARTIFACT_DIR" \
    --pattern "php_$PHP_VERSION$suffix-dbgsym+$ID$VERSION_ID$arch_suffix.tar.zst"
  # Preserve core debug symbols, discarding the old custom-extension symbols.
  bash scripts/stage-package-extensions.sh
fi
extension_dir=$("php-config$PHP_VERSION" --extension-dir)
include_dir=$("php-config$PHP_VERSION" --include-dir)
for root in "/tmp/debian/php$PHP_VERSION" /; do
  for extension in $EXTENSIONS_TO_BUILD; do
    find "$root/$extension_dir" -maxdepth 1 -name "$extension.so" -delete
    find "$root/etc/php/$PHP_VERSION" -type l -name "*-$extension.ini" -delete
    rm -rf "$root/${include_dir:?}/ext/$extension"
  done
done

# Source packages can contain older library overlays. Reinstall the current
# versions before compiling extensions or recording the dependency fingerprint.
bash scripts/lib/install.sh --php-version "$PHP_VERSION"
bash scripts/lib/install.sh --php-version "$PHP_VERSION" --root "/tmp/debian/php$PHP_VERSION"

# Cache builds can download PECL sources directly without bootstrapping PEAR.
[ "${EXTENSIONS_CACHE_ONLY:-false}" != true ] || exit 0

# Published packages omit PEAR/PECL; install.sh normally bootstraps them after
# extraction. Provide the same tools in this packaging environment as well.
pear_installer=$(mktemp /tmp/php-cache-pear.XXXXXXXX)
trap 'rm -f "$pear_installer"' EXIT
curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 \
  https://raw.githubusercontent.com/pear/pearweb_phars/master/install-pear-nozlib.phar -o "$pear_installer"
INSTALL_ROOT='' "php$PHP_VERSION" "$pear_installer" -p "/usr/bin/php$PHP_VERSION"
pecl -V
