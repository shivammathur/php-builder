#!/usr/bin/env bash

get() {
  file_path=$1
  shift
  links=("$@")
  command -v sudo >/dev/null && SUDO=sudo
  for link in "${links[@]}"; do
    status_code=$(${SUDO} curl -w "%{http_code}" -o "$file_path" -sL "$link")
    [ "$status_code" = "200" ] && break
  done
}

set_base_version_id() {
  [[ "$ID" =~ ubuntu|debian ]] && return;
  for base in ubuntu debian; do
    [[ "$ID_LIKE" =~ $base ]] && ID="$base" && VERSION_ID="$(grep "$VERSION_CODENAME" /tmp/os_releases.json | grep -Eo '[0-9]+(\.[0-9]+(\.[0-9]+)?)?')" && break
  done
}

set_base_version_codename() {
  [[ "$ID" =~ ubuntu|debian ]] && return;
  get /tmp/os_releases.json https://raw.githubusercontent.com/shivammathur/php-builder/main/config/os_releases.json
  if [[ "$ID_LIKE" =~ ubuntu ]]; then
    [[ -n "$UBUNTU_CODENAME" ]] && VERSION_CODENAME="$UBUNTU_CODENAME" && return;
    [ -e "$upstream_lsb" ] && VERSION_CODENAME=$(grep 'CODENAME' "$upstream_lsb" | cut -d '=' -f 2) && return;
    VERSION_CODENAME=$(grep -E 'deb.*ubuntu.com' "$list_file" | head -n 1 | cut -d ' ' -f 3) && VERSION_CODENAME=${VERSION_CODENAME%-*}
  elif [[ "$ID_LIKE" =~ debian ]] || command -v apt >/dev/null; then
    ID_LIKE=debian
    [[ -n "$DEBIAN_CODENAME" ]] && VERSION_CODENAME="$DEBIAN_CODENAME" && return;
    update_lists && VERSION_CODENAME=$(apt-cache show tzdata | grep Provides | head -n 1 | cut -f2 -d '-')
  fi
}

set_base_version() {
  if [ -e /tmp/os-release ]; then
    . /tmp/os-release
  else
    set_base_version_codename
    set_base_version_id
    printf "ID=%s\nVERSION_ID=%s\nVERSION_CODENAME=%s\n" "$ID" "$VERSION_ID" "$VERSION_CODENAME" | tee /tmp/os-release >/dev/null 2>&1
  fi
}

update_lists_helper() {
  list=$1
  command -v sudo >/dev/null && SUDO=sudo
  if [[ -n "$list" ]]; then
    ${SUDO} apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
  else
    ${SUDO} apt-get update
  fi
}

update_lists() {
  local ppa=${1:-}
  local ppa_search=${2:-}
  if [ ! -e /tmp/setup_php ] || [[ -n $ppa && -n $ppa_search ]]; then
    if [[ -n "$ppa" && -n "$ppa_search" ]]; then
      list="$list_dir"/"$(basename "$(grep -lr "$ppa_search" "$list_dir")")"
    elif grep -Eq '^deb ' "$list_file"; then
      list="$list_file"
    fi
    update_lists_helper "$list"
    echo '' | tee /tmp/setup_php >/dev/null 2>&1
  fi
}

ubuntu_fingerprint() {
  curl -sL "$lp_api"/~"${ppa%/*}"/+archive/"${ppa##*/}" | jq -r '.signing_key_fingerprint'
}

debian_fingerprint() {
  release_pub=/tmp/"${ppa/\//-}".gpg
  get "$release_pub" "$ppa_url"/dists/"$package_dist"/Release.gpg
  gpg --list-packets "$release_pub" | grep -Eo 'fpr\sv4\s.*[a-zA-Z0-9]+' | head -n 1 | cut -d ' ' -f 3
}

add_key() {
  ppa=${1:-ondrej/php}
  package_dist=$2
  key_source=$3
  key_file=$4
  key_urls=("$key_source")
  if [[ "$key_source" =~ launchpad.net|debian.org|setup-php.com ]]; then
    fp=$("${ID}"_fingerprint) && key_urls=("$ubuntu_sks/$sks_uri=0x$fp" "$mit_sks/$sks_uri=0x$fp")
  fi
  [ ! -e "$key_source" ] && get "$key_file" "${key_urls[@]}"
  if [[ "$(file "$key_file")" =~ .*('Public-Key (old)'|'Secret-Key') ]]; then
    sudo gpg --batch --yes --dearmor "$key_file" && sudo rm -f "$key_file" >/dev/null 2>&1
    sudo mv "$key_file".gpg "$key_file"
  fi
}

add_list() {
  ppa=${1-ondrej/php}
  ppa_url=${2:-"$lp_ppa/$ppa/ubuntu"}
  key_source=${3:-"$ppa_url"}
  package_dist=${4:-"$VERSION_CODENAME"}
  branches=${5:-main}
  ppa_search="deb .*$ppa_url $package_dist .*$branches"
  grep -Eqr "$ppa_search" "$list_dir" && echo "Repository $ppa already exists" && return;
  arch=$(dpkg --print-architecture)
  [ -e "$key_source" ] && key_file=$key_source || key_file="$key_dir"/"${ppa/\//-}"-keyring.gpg
  add_key "$ppa" "$package_dist" "$key_source" "$key_file"
  echo "deb [arch=$arch signed-by=$key_file] $ppa_url $package_dist $branches" | sudo tee "$list_dir"/"${ppa/\//-}".list >/dev/null 2>&1
  update_lists "$ppa" "$ppa_search"
}

remove_list() {
  ppa=${1-ondrej/php}
  ppa_url=${2:-"$lp_ppa/$ppa/ubuntu"}
  grep -lr "$ppa_url" "$list_dir" | xargs -n1 sudo rm -f
  sudo rm -f "$key_dir"/"${ppa/\//-}"-keyring || true
}

add_ppa() {
  if [ "$ID" = "ubuntu" ]; then
    add_list ubuntu-toolchain-r/test
    if [ "$VERSION_ID" = "16.04" ]; then
      remove_list ondrej/php
      add_list ondrej/php https://setup-php.com/ondrej/php/ubuntu
    else
      add_list ondrej/php
    fi
  elif [ "$ID" = "debian" ]; then
    add_list ondrej/php https://packages.sury.org/php/ https://packages.sury.org/php/apt.gpg
    add_list debian/testing http://deb.debian.org/debian '' testing main
  fi
}

install_packages() {
  packages=("$@")
  apt_mgr='apt-get'
  command -v apt-fast >/dev/null && apt_mgr='apt-fast'
  apt_install="sudo $debconf_fix $apt_mgr install -y --no-install-recommends"
  $apt_install "${packages[@]}" || (update_lists && $apt_install "${packages[@]}")
}

add_prerequisites() {
  prerequisites=()
  command -v sudo >/dev/null && SUDO=sudo || prerequisites+=('sudo')
  command -v curl >/dev/null || prerequisites+=('curl')
  command -v zstd >/dev/null || prerequisites+=('zstd')
  update_lists && ${SUDO} apt-get install -y "${prerequisites[@]}"
}

local_deps() {
  install_packages apt-transport-https ca-certificates file gnupg jq zstd
  enchant=$(apt-cache show libenchant-?[0-9]+?-dev | grep 'Package' | head -n 1 | cut -d ' ' -f 2)
  add_ppa
  install_packages gcc-9 g++-9 libargon2-dev "$enchant" libmagickwand-dev libpq-dev libfreetype6-dev libicu-dev libjpeg-dev libpng-dev libonig-dev libxslt1-dev libaspell-dev libcurl4-gnutls-dev libc-client2007e-dev libkrb5-dev libldap-dev liblz4-dev libmemcached-dev libgomp1 librabbitmq-dev libsodium-dev libtidy-dev libwebp-dev libxpm-dev libzip-dev libzstd-dev systemd unixodbc-dev
}

github_deps() {
  if [ "$VERSION_ID" = "16.04" ]; then
    get /tmp/webp.deb http://archive.ubuntu.com/ubuntu/pool/main/libw/libwebp/libwebp6_0.6.1-2_amd64.deb
    sudo dpkg -i /tmp/webp.deb
  elif [ "$VERSION_ID" = "18.04" ]; then
    get /tmp/libsodium.deb http://archive.ubuntu.com/ubuntu/pool/main/libs/libsodium/libsodium23_1.0.18-1_amd64.deb
    sudo dpkg -i /tmp/libsodium.deb
  fi
}

switch_version() {
  sudo rm -rf /usr/bin/php*"$version" /usr/bin/pecl /usr/bin/pear* 2>/dev/null || true
  sudo cp -f "$install_dir"/usr/lib/cgi-bin/php"$version" /usr/lib/cgi-bin/
  sudo update-alternatives --install /usr/lib/libphp"${version/%.*}".so libphp"${version/%.*}" "$install_dir"/usr/lib/libphp"$version".so 50 && sudo ldconfig
  sudo update-alternatives --install /usr/lib/cgi-bin/php php-cgi-bin /usr/lib/cgi-bin/php"$version" 50
  sudo update-alternatives --set php-cgi-bin /usr/lib/cgi-bin/php"$version"
  to_wait_arr=()
  for tool_path in "$install_dir"/bin/*; do
    (
      tool=$(basename "$tool_path")
      sudo cp "$tool_path" /usr/bin/"$tool$version"
      sudo update-alternatives --install /usr/bin/"$tool" "$tool" /usr/bin/"$tool$version" 50
      sudo update-alternatives --set "$tool" /usr/bin/"$tool$version"
    ) &
    to_wait_arr+=( $! )
  done
  wait "${to_wait_arr[@]}"
}

link_prefix() {
  sudo cp -f "$install_dir"/COMMIT /etc/php/"$version"/COMMIT
  sudo cp -f "$install_dir"/etc/init.d/php"$version"-fpm /etc/init.d/
  sudo cp -f "$install_dir"/usr/lib/tmpfiles.d/php"$version"-fpm.conf /usr/lib/tmpfiles.d/
  sudo cp -f "$install_dir"/etc/systemd/system/php"$version"-fpm.service /lib/systemd/system/
  sudo cp -f "$install_dir"/usr/lib/apache2/modules/libphp"$version".so /usr/lib/apache2/modules/
  sudo cp -f "$install_dir"/etc/apache2/mods-available/* /etc/apache2/mods-available/
  sudo cp -f "$install_dir"/etc/apache2/conf-available/* /etc/apache2/conf-available/
  sudo cp -f "$install_dir"/etc/apache2/sites-available/* /etc/apache2/sites-available/
  sudo cp -f "$install_dir"/etc/nginx/sites-available/* /etc/nginx/sites-available/
}

install() {
  if [ "$1" != "github" ]; then
    add_prerequisites
    set_base_version
    local_deps &
  else
    github_deps &
  fi
  to_wait=$!
  tar_file="php_$version+$ID$VERSION_ID.tar.zst"
  get "/tmp/$tar_file" "https://github.com/shivammathur/php-builder/releases/latest/download/$tar_file"
  sudo mkdir -m 777 -p /var/run /run/php /etc/php/"$version" /usr/local/php /usr/lib/cgi-bin/ /usr/include/php /lib/systemd/system /usr/lib/tmpfiles.d /etc/apache2/mods-available /etc/apache2/conf-available /etc/apache2/sites-available /etc/nginx/sites-available /usr/lib/apache2/modules
  sudo tar -I zstd -xf "/tmp/$tar_file" -C /usr/local/php --no-same-owner
  wait "$to_wait"
  . /etc/os-release
}

configure() {
  echo '' | sudo tee "$pecl_file"
  for script in pear pecl; do
    sudo "$script" config-set php_ini "$pecl_file"
    sudo "$script" channel-update "$script".php.net
  done
  echo '' | sudo tee /tmp/pecl_config
  (
    echo "opcache.enable=1"
    echo "opcache.jit_buffer_size=256M"
    echo "opcache.jit=1235"
  ) >>"$install_dir"/etc/php.ini
  sudo chmod a+x "$install_dir"/bin/php-fpm-socket-helper
  sudo ln -sf "$install_dir"/include/php /usr/include/php/"$(php-config --extension-dir | grep -Eo -m 1 "[0-9]{8}")"
  sudo ln -sf "$install_dir"/etc/php.ini /etc/php.ini
  sudo ln -sf "$install_dir"/etc/php.ini /etc/php/"$version"/php.ini
  sudo service php"$version"-fpm start || true
}

# Read version correctly
if [ "$1" = "github" ]; then
  runner="github"
  version=${2:-8.1}
elif [[ "$1" =~ local|self-hosted ]]; then
  runner="local"
  version="$2"
elif [[ "$2" =~ local|self-hosted|github ]]; then
  runner="$2"
  version="$1"
else
  runner="local"
  version="$1"
fi

install_dir="/usr/local/php/$version"
pecl_file="$install_dir/etc/conf.d/99-pecl.ini"
list_file='/etc/apt/sources.list'
list_dir="$list_file.d"
debconf_fix='DEBIAN_FRONTEND=noninteractive'
upstream_lsb='/etc/upstream-release/lsb-release'
lp_api='https://api.launchpad.net/1.0'
lp_ppa='http://ppa.launchpad.net'
key_dir='/usr/share/keyrings'
mit_sks='http://pgp.mit.edu'
ubuntu_sks='https://keyserver.ubuntu.com'
sks_uri='pks/lookup?op=get&options=mr&exact=on&search'
. /etc/os-release
install "$runner"
link_prefix
switch_version
configure
