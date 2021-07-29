#!/usr/bin/env bash

get() {
  file_path=$1
  shift
  links=("$@")
  for link in "${links[@]}"; do
    status_code=$(sudo curl -w "%{http_code}" -o "$file_path" -sL "$link")
    [ "$status_code" = "200" ] && break
  done
}

cleanup_lists() {
  ppa=${1:-ondrej/php}
  rm -rf /etc/apt/sources.list.d.save
  sudo mv /etc/apt/sources.list.d /etc/apt/sources.list.d.save
  sudo mkdir /etc/apt/sources.list.d
  sudo mv /etc/apt/sources.list.d.save/*"${ppa%/*}"*.list /etc/apt/sources.list.d/ 2>/dev/null || true
}

restore_lists() {
  sudo mv /etc/apt/sources.list.d.save/*.list /etc/apt/sources.list.d/ 2>/dev/null || true
}

update_lists_helper() {
  ppa=$1
  list="$(basename "$(grep -r "$ppa" /etc/apt/sources.list.d | cut -d ':' -f 1)")"
  if [ "x$ppa" != "x" ] && [ "x$list" != "x" ]; then
    sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/$list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
  else
    cleanup_lists 'ondrej/php' && sudo apt-get update && restore_lists
  fi
}

update_lists() {
  force=$1
  ppa=$2
  if [ ! -e /tmp/setup_php ] || [ "$force" = "--force" ]; then
    update_lists_helper "$ppa"
    echo '' | sudo tee /tmp/setup_php >/dev/null 2>&1
  fi
}

get_ppa_key() {
  ppa=${1-ondrej/php}
  curl -sL https://api.launchpad.net/1.0/~"${ppa%/*}"/+archive/"${ppa##*/}" | jq -r '.signing_key_fingerprint'
}

add_list () {
  ppa=${1-ondrej/php}
  url=${2:-"http://ppa.launchpad.net/$ppa/ubuntu"}
  key_url=$3
  os_version=${4:-$VERSION_CODENAME}
  branch=${5:-main}
  arch=${6:-}
  if [ "$(grep -r "$ppa" /etc/apt/sources.list.d | wc -l)" = "0" ]; then
    echo "deb $arch $url $os_version $branch" > /etc/apt/sources.list.d/"${ppa%/*}".list
    if [[ -n "${key_url// /}" ]]; then
      get /etc/apt/trusted.gpg.d/"${ppa%/*}".gpg "$key_url"
    elif [[ "$url" =~ launchpad.net|setup-php.com ]]; then
      apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$(get_ppa_key "$ppa")"
    fi
    update_lists --force "$ppa"
  else
    echo "PPA $ppa found in APT sources"
  fi
}

remove_list () {
  ppa=${1-ondrej/php}
  find /etc/apt/sources.list.d -name "$ppa" -exec rm -f {} \;
  apt-key del "$(get_ppa_key "$ppa")" || true
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
    add_list php/ https://packages.sury.org/php/ https://packages.sury.org/php/apt.gpg
    add_list debian http://deb.debian.org/debian '' testing main
  fi
}

install_packages() {
  apt_tool=$1
  shift 1
  packages=("$@")
  apt_install="sudo $debconf_fix $apt_tool install -y --no-install-recommends"
  $apt_install "${packages[@]}" || (update_lists && $apt_install "${packages[@]}")
}

local_prerequisites() {
  if ! command -v sudo >/dev/null; then
    apt-get update && apt-get install -y sudo;
    echo '' | sudo tee /tmp/setup_php >/dev/null 2>&1
  fi
  if ! command -v apt-fast >/dev/null; then
    get /usr/local/bin/apt-fast https://raw.githubusercontent.com/ilikenwf/apt-fast/master/apt-fast && sudo chmod a+x /usr/local/bin/apt-fast
    get /etc/apt-fast.conf https://raw.githubusercontent.com/ilikenwf/apt-fast/master/apt-fast.conf
    if ! command -v apt-fast >/dev/null; then
      sudo ln -sf /usr/bin/apt-get /usr/bin/apt-fast
      trap "sudo rm -f /usr/bin/apt-fast 2>/dev/null" exit
    fi
  fi
}

local_deps() {
  install_packages apt-get apt-transport-https aria2 ca-certificates curl gnupg jq zstd
  add_ppa
  enchant=libenchant-dev
  [ "$VERSION_ID" = "20.04" ] || [ "$VERSION_ID" = "11" ] && enchant=libenchant-2-dev
  install_packages apt-fast gcc-9 g++-9 libargon2-dev "$enchant" libmagickwand-dev libpq-dev libfreetype6-dev libicu-dev libjpeg-dev libpng-dev libonig-dev libxslt1-dev libaspell-dev libcurl4-gnutls-dev libc-client2007e-dev libkrb5-dev libldap-dev liblz4-dev libmemcached-dev libgomp1 librabbitmq-dev libsodium-dev libtidy-dev libwebp-dev libxpm-dev libzip-dev libzstd-dev unixodbc-dev
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
  sudo cp -f "$install_dir"/etc/systemd/system/php"$version"-fpm.service /lib/systemd/system/
  sudo cp -f "$install_dir"/usr/lib/apache2/modules/libphp"$version".so /usr/lib/apache2/modules/
  sudo cp -f "$install_dir"/etc/apache2/mods-available/* /etc/apache2/mods-available/
  sudo cp -f "$install_dir"/etc/apache2/conf-available/* /etc/apache2/conf-available/
}

install() {
  if [ "$1" != "github" ]; then
    local_prerequisites
    local_deps &
  else
    github_deps &
  fi
  to_wait=$!
  tar_file="php_$version+$ID$VERSION_ID.tar.zst"
  get "/tmp/$tar_file" "https://github.com/shivammathur/php-builder/releases/latest/download/$tar_file"
  sudo mkdir -m 777 -p /var/run /run/php /etc/php/"$version" /usr/local/php /usr/lib/cgi-bin/ /usr/include/php /lib/systemd/system /etc/apache2/mods-available /etc/apache2/conf-available /usr/lib/apache2/modules
  wait "$to_wait"
  sudo tar -I zstd -xf "/tmp/$tar_file" -C /usr/local/php --no-same-owner
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
  if ! sudo grep -Eq '(actions_job|containerd|docker|lxc)' /proc/1/cgroup && [ ! -e .dockerenv ] && [ ! -e /run/.dockerenv ] && [ ! -e /run/.containerenv ]; then
    sudo service php"$version"-fpm start || true
  fi
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
debconf_fix="DEBIAN_FRONTEND=noninteractive"
. /etc/os-release
install "$runner"
link_prefix
switch_version
configure
