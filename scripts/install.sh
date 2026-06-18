#!/usr/bin/env bash

# Function to print usage help
print_help() {
  cat << HELP > /dev/stdout

Usage: ${0} [--remove] <php-version>

HELP
}

get() {
  mode=$1
  file_path=$2
  shift 2
  links=("$@")
  if [ "$mode" = "-s" ]; then
    sudo curl -sL "${links[0]}"
  else
    for link in "${links[@]}"; do
      status_code=$(sudo curl -w "%{http_code}" -o "$file_path" -sL "$link")
      [ "$status_code" = "200" ] && break
    done
  fi
}

set_base_version_id() {
  [[ "$ID" =~ ubuntu|debian ]] && return;
  if ! [ -d "$dist_info_dir" ]; then
    sudo mkdir -p "$dist_info_dir"
    get -q "$dist_info_dir"/os_releases.csv https://raw.githubusercontent.com/shivammathur/setup-php/develop/src/configs/os_releases.csv
  fi
  for base in ubuntu debian; do
    [[ "$ID_LIKE" =~ $base ]] && ID="$base" && VERSION_ID="$(grep -hr -m 1 "$VERSION_CODENAME" /usr/share/distro-info | cut -d ',' -f 1 | cut -d ' ' -f 1)" && break
  done
}

set_base_version_codename() {
  [[ "$ID" =~ ubuntu|debian ]] && return;
  if [[ "$ID_LIKE" =~ ubuntu ]]; then
    [[ -n "$UBUNTU_CODENAME" ]] && VERSION_CODENAME="$UBUNTU_CODENAME" && return;
    [ -e "$upstream_lsb" ] && VERSION_CODENAME=$(grep 'CODENAME' "$upstream_lsb" | cut -d '=' -f 2) && return;
    VERSION_CODENAME=$(grep -E -m1 'deb .*ubuntu.com' "$list_file" | cut -d ' ' -f 3) && VERSION_CODENAME=${VERSION_CODENAME%-*}
  elif [[ "$ID_LIKE" =~ debian ]] || command -v dpkg >/dev/null; then
    ID_LIKE=debian
    [[ -n "$DEBIAN_CODENAME" ]] && VERSION_CODENAME="$DEBIAN_CODENAME" && return;
    update_lists && VERSION_CODENAME=$(apt-cache show tzdata | grep -m 1 Provides | cut -d '-' -f 2)
  fi
}

set_base_version() {
  DIST_ID="$ID"
  if [ -e /tmp/os-release ]; then
    . /tmp/os-release
  else
    set_base_version_codename
    set_base_version_id
    printf "ID=%s\nVERSION_ID=%s\nVERSION_CODENAME=%s\n" "$ID" "$VERSION_ID" "$VERSION_CODENAME" | tee /tmp/os-release >/dev/null 2>&1
  fi
}

update_lists() {
  if [ ! -e /tmp/setup_php ]; then
    ${SUDO} apt-get update && echo '' | tee /tmp/setup_php >/dev/null 2>&1
  fi
}

fix_broken_packages() {
  sudo apt --fix-broken install >/dev/null 2>&1
}

install_packages() {
  packages=("$@")
  apt_mgr='apt-get'
  command -v apt-fast >/dev/null && apt_mgr='apt-fast'
  apt_install="sudo $debconf_fix $apt_mgr install -y --no-install-recommends"
  $apt_install "${packages[@]}" || (update_lists && fix_broken_packages && $apt_install "${packages[@]}")
}

add_prerequisites() {
  prerequisites=()
  command -v sudo >/dev/null && SUDO=sudo || prerequisites+=('sudo')
  command -v curl >/dev/null || prerequisites+=('curl')
  command -v zstd >/dev/null || prerequisites+=('zstd')
  update_lists
  if [ "${#prerequisites[@]}" -gt 0 ]; then
    ${SUDO} apt-get install -y "${prerequisites[@]}"
    command -v sudo >/dev/null && SUDO=sudo
  fi
}

add_pear() {
  if ! [ -e /usr/bin/pear ]; then
    sudo curl -o /tmp/pear.phar -sL https://raw.githubusercontent.com/pear/pearweb_phars/master/install-pear-nozlib.phar
    sudo php /tmp/pear.phar && sudo rm -f /tmp/pear.phar
    to_wait=()
    for script in pear pecl; do
      sudo "$script" channel-update "$script".php.net &
      to_wait+=("$!")
    done
    wait "${to_wait[@]}"
  fi
}

local_deps() {
  local deps libenchant_dev
  libenchant_dev=$(apt-cache show libenchant-?[0-9]+?-dev | grep 'Package' | head -n 1 | cut -d ' ' -f 2)
  deps=(apt-transport-https ca-certificates file gnupg jq zstd gcc g++ autoconf firebird-dev freetds-dev libacl1-dev libapparmor-dev libargon2-dev libaspell-dev libavif-dev libbrotli-dev libc-ares-dev libcurl4-openssl-dev libdb-dev libedit-dev "$libenchant_dev" libevent-dev libfreetype6-dev libheif-dev libraqm-dev libimagequant-dev libgearman-dev libgomp1 libgpgme-dev libicu-dev libjpeg-dev libkrb5-dev libldap-dev liblmdb-dev liblz4-dev libmagickwand-dev libmaxminddb-dev libmcrypt-dev libmemcached-dev libnghttp2-dev libonig-dev libpng-dev libpq-dev libqdbm-dev librabbitmq-dev librdkafka-dev librrd-dev libsmbclient-dev libsnmp-dev libsodium-dev libsqlite3-dev libssh2-1-dev libssl-dev libtidy-dev libtool libwebp-dev libwrap0-dev libxpm-dev libxml2-dev libxmlrpc-epi-dev libxslt1-dev libyaml-dev libzip-dev libzmq3-dev libzstd-dev make patch php-common shtool snmp systemd tzdata unixodbc-dev uuid-dev)
  install_packages "${deps[@]}"
}

github_deps() {
  local deps
  deps=(libavif-dev libevent-dev libfreetype6-dev libgearman-dev libheif-dev libimagequant-dev libjpeg-dev libmcrypt-dev libpng-dev libraqm-dev librdkafka-dev librrd-dev libsmbclient-dev libssh2-1-dev libtiff-dev libwebp-dev libxpm-dev zlib1g-dev)
  if [ "$VERSION_ID" = "22.04" ]; then
    deps+=('libxmlrpc-epi-dev')
    [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && deps+=('unixodbc-dev')
  elif [ "$VERSION_ID" = "24.04" ]; then
    deps+=('unixodbc-dev' 'libmagickcore-dev' 'libxmlrpc-epi-dev')
  elif [ "$VERSION_ID" = "26.04" ]; then
    deps+=('unixodbc-dev' 'libmagickcore-dev' 'libxmlrpc-epi-dev')
  fi
  install_packages "${deps[@]}"
}

switch_version() {
  sudo update-alternatives --install /usr/lib/libphp"${version/%.*}".so libphp"${version/%.*}" /usr/lib/libphp"$version".so "${version/./}" && sudo ldconfig
  sudo update-alternatives --install /usr/lib/cgi-bin/php php-cgi-bin /usr/lib/cgi-bin/php"$version" "${version/./}"
  sudo update-alternatives --install /usr/sbin/php-fpm php-fpm /usr/sbin/php-fpm"$version" "${version/./}"
  sudo update-alternatives --set php-cgi-bin /usr/lib/cgi-bin/php"$version"
  sudo update-alternatives --set php-fpm /usr/sbin/php-fpm"$version"
  to_wait_arr=()
  for tool in phar phar.phar php-config phpize php php-cgi phpdbg; do
    (
      sudo update-alternatives --install /usr/bin/"$tool" "$tool" /usr/bin/"$tool$version" "${version/./}" \
                               --slave /usr/share/man/man1/"$tool".1 "$tool".1 /usr/share/man/man1/"$tool$version".1
      sudo update-alternatives --set "$tool" /usr/bin/"$tool$version"
    ) &
    to_wait_arr+=( $! )
  done
  wait "${to_wait_arr[@]}"
}

relocate_build() {
  build_dir=$1
  if [ -d "$build_dir"/lib ] && [ -h /lib ]; then
    sudo cp -rf "$build_dir"/lib/* "$build_dir"/usr/lib/
    sudo rm -rf "${build_dir:?}"/lib
  fi
  sudo cp -rf "$build_dir"/* /
}

extract_build() {
  tar_file=$1
  build_dir=$2
  if [[ "$DIST_ID" =~ ubuntu|debian ]]; then
    sudo tar -I zstd -xf "/tmp/$tar_file" -C / --no-same-owner
  else
    sudo tar -I zstd -xf "/tmp/$tar_file" -C "$build_dir" --no-same-owner
    relocate_build "$build_dir"
  fi
}

install() {
  to_wait=()
  arch="$(arch)"
  [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && ARCH_SUFFIX='_arm64' || ARCH_SUFFIX=''
  if [ "$1" != "github" ]; then
    add_prerequisites
    set_base_version
    local_deps &
    to_wait=("$!")
  else
    github_deps &
    to_wait=("$!")
  fi
  tar_file="php_$version$PHP_PKG_SUFFIX+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"
  get -q "/tmp/$tar_file" "https://github.com/shivammathur/php-builder/releases/download/$version/$tar_file"
  sudo rm -rf /etc/php/"$version" /tmp/php"$version"
  sudo mkdir -m 777 -p /tmp/php"$version" /var/run /run/php /lib/systemd/system /usr/lib/tmpfiles.d /etc/apache2/mods-available /etc/apache2/conf-available /etc/apache2/sites-available /etc/nginx/sites-available /usr/lib/apache2/modules
  extract_build "$tar_file" /tmp/php"$version"
  [[ -n ${to_wait[*]// } ]] && wait "$to_wait"
  . /etc/os-release
}

configure() {
  if [ "$runner" = "github" ]; then
    sudo rm -f "$pecl_file"
    pecl_file="/etc/php/$version/cli/conf.d/99-pecl.ini"
    sudo touch "$pecl_file"
    for sapi in $(php-config"$version" --php-sapis | sed -E -e 's/cli |handler//g'); do
      sudo ln -sf "$pecl_file" /etc/php/"$version"/"$sapi"/conf.d/99-pecl.ini
    done
  fi
  sudo chmod 777 "$pecl_file"
  echo system user | xargs -n1 sudo pear config-set php_ini "$pecl_file"
  echo '' | sudo tee /tmp/pecl_config >/dev/null 2>&1
  if [ -d /run/systemd/system ]; then
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable php"$version"-fpm 2>/dev/null || true
  fi
  sudo service php"$version"-fpm restart || true
}

get_api_version_from_repo() {
  php_header="https://raw.githubusercontent.com/php/php-src/PHP-$version/main/php.h"
  status_code=$(curl -sSL -o /tmp/php.h -w "%{http_code}" "$php_header")
  if [ "$status_code" != "200" ]; then
    curl -sL "${php_header/PHP-$version/master}" | grep "PHP_API_VERSION" | cut -d' ' -f 3
  else
    grep "PHP_API_VERSION" /tmp/php.h | cut -d' ' -f 3
  fi
}

remove() {
  if ! [ -e /usr/bin/php"${version:?}" ]; then
    echo "Error: PHP $version is not installed"
    return 1;
  else
    phpapi="$(get_api_version_from_repo)"
  fi
  command -v sudo >/dev/null || (update_lists && apt-get install -y sudo)
  if [ -e /etc/init.d/php"$version"-fpm ]; then
    sudo service php"$version"-fpm stop || true
    if [ -d /run/systemd/system ]; then
      sudo systemctl disable php"$version"-fpm
      sudo systemctl daemon-reload
      sudo systemctl reset-failed
    fi
  fi
  [ -e /usr/lib/libphp"$version".so ] && sudo update-alternatives --remove libphp"${version/%.*}" /usr/lib/libphp"$version".so && sudo ldconfig
  [ -e /usr/lib/cgi-bin/php"$version" ] && sudo update-alternatives --remove php-cgi-bin /usr/lib/cgi-bin/php"$version"
  [ -e /usr/sbin/php-fpm"$version" ] && sudo update-alternatives --remove php-fpm /usr/sbin/php-fpm"$version"
  for tool in phar phar.phar php-config phpize php php-cgi phpdbg; do
    if [ -e /usr/bin/"$tool$version" ]; then
      sudo update-alternatives --remove "$tool" /usr/bin/"$tool$version"
      sudo rm -f /usr/bin/"$tool$version"
    fi
  done
  sudo find /etc /usr/share/man -name "php$version*" -delete
  sudo rm -rf /lib/systemd/system/php"$version"-fpm.service \
              /usr/lib/systemd/system/php"$version"-fpm.service \
              /etc/logrotate.d/php"$version"-fpm \
              /etc/php/"$version" \
              /usr/include/php/"$phpapi" \
              /usr/lib/libphp"$version".so \
              /usr/lib/apache2/modules/libphp"$version".so \
              /usr/lib/cgi-bin/php"$version" \
              /usr/lib/php/php"$version"-fpm-reopenlogs \
              /usr/lib/php/"$version" \
              /usr/lib/php/"${phpapi:?}" \
              /usr/lib/tmpfiles.d/php"$version"-fpm.conf \
              /usr/lib/libphp"$version".so \
              /usr/sbin/php-fpm"$version" \
              /usr/share/php/"$version"
  return 0;
}

# avoid running without arguments
if [[ "${#}" -eq 0 ]]; then
  print_help
  exit 0;
fi

if [[ "$1" =~ remove ]]; then
  version=$2
  remove
  exit $?
elif [[ "$2" =~ remove ]]; then
  version=$1
  remove
  exit $?
fi

for arg in "$@"; do
  if [[ "$arg" =~ ^[0-9]+\.[0-9]+$ ]]; then
    version="$arg"
  elif [[ "$arg" =~ local|self-hosted ]]; then
    runner="local"
  elif [[ "$arg" =~ github ]]; then
    runner="github"
  elif [[ "$arg" =~ release|debug ]]; then
    debug="$arg"
  elif [[ "$arg" =~ nts|zts ]]; then
    build="$arg"
  fi
done

[[ -z "$version" ]] && version=8.1
[[ -z "$runner" ]] && runner=local
[[ -z "$debug" ]] && debug=release
[[ -z "$build" ]] && build=nts

if ! [[ $version =~ ^(5\.6|7\.[0-4]|8\.[0-6])$ ]]; then
  echo "Version $version is not supported";
  exit 1;
fi

PHP_PKG_SUFFIX=
if [ "${build:?}" = "zts" ]; then
  PHP_PKG_SUFFIX="-zts"
fi
if [ "$debug" = "debug" ]; then
  PHP_PKG_SUFFIX="$PHP_PKG_SUFFIX-dbgsym"
fi
. /etc/os-release
pecl_file="/etc/php/$version/mods-available/pecl.ini"
debconf_fix='DEBIAN_FRONTEND=noninteractive'
list_dir='/etc/apt/sources.list.d'
list_file="$list_dir/$ID.sources"
[ -e "$list_file" ] || list_file='/etc/apt/sources.list'
upstream_lsb='/etc/upstream-release/lsb-release'
dist_info_dir='/usr/share/distro-info'
command -v sudo >/dev/null && SUDO=sudo || SUDO=
install "$runner"
switch_version
add_pear
configure
