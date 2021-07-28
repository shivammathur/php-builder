#!/usr/bin/env bash

add_ppa() {
  if [ "$ID" = "ubuntu" ]; then
    sudo apt-add-repository ppa:ubuntu-toolchain-r/test -y
    if [ "$VERSION_ID" = "16.04" ]; then
      LC_ALL=C.UTF-8 sudo apt-add-repository --remove ppa:ondrej/php -y || true
      LC_ALL=C.UTF-8 sudo apt-add-repository https://setup-php.com/ondrej/php/ubuntu -y
      sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 4f4ea0aae5267a6c
      sudo apt-get update
    elif ! apt-cache policy | grep -q "ondrej/php"; then
      LC_ALL=C.UTF-8 sudo apt-add-repository ppa:ondrej/php -y
    fi
  elif [ "$ID" = "debian" ]; then
    get /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/ondrej.list
    echo "deb http://deb.debian.org/debian testing main" > /etc/apt/sources.list.d/testing.list
    sudo apt-get update
  fi
}

local_deps() {
  if ! command -v sudo >/dev/null; then apt-get install -y sudo; fi
  if ! command -v apt-fast >/dev/null; then
    sudo ln -sf /usr/bin/apt-get /usr/bin/apt-fast
    trap "sudo rm -f /usr/bin/apt-fast 2>/dev/null" exit
  fi
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-fast install -y apt-transport-https curl software-properties-common zstd gnupg systemd
  add_ppa
  enchant=libenchant-dev
  [ "$VERSION_ID" = "20.04" ] || [ "$VERSION_ID" = "11" ] && enchant=libenchant-2-dev
  sudo DEBIAN_FRONTEND=noninteractive apt-fast install -f -y gcc-9 g++-9 libargon2-dev "$enchant" libmagickwand-dev libpq-dev libfreetype6-dev libicu-dev libjpeg-dev libpng-dev libonig-dev libxslt1-dev libaspell-dev libcurl4-gnutls-dev libc-client2007e-dev libkrb5-dev libldap-dev liblz4-dev libmemcached-dev libgomp1 librabbitmq-dev libsodium-dev libtidy-dev libwebp-dev libxpm-dev libzip-dev libzstd-dev unixodbc-dev
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

get() {
  file_path=$1
  shift
  links=("$@")
  for link in "${links[@]}"; do
    status_code=$(sudo curl -w "%{http_code}" -o "$file_path" -sL "$link")
    [ "$status_code" = "200" ] && break
  done
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
. /etc/os-release
install "$runner"
link_prefix
switch_version
configure
