#!/usr/bin/env bash

add_ppa() {
  if ! apt-cache policy | grep -q ondrej/php; then
    LC_ALL=C.UTF-8 sudo apt-add-repository ppa:ondrej/php -y
    if [ "$VERSION_ID" = "16.04" ]; then
      sudo "$debconf_fix" apt-get update >/dev/null 2>&1
    fi
  fi
}

local_deps() {
  if ! command -v apt-fast >/dev/null; then sudo ln -sf /usr/bin/apt-get /usr/bin/apt-fast; fi
  sudo "$debconf_fix" apt-get update
  sudo "$debconf_fix" apt-fast install -y curl software-properties-common zstd
  add_ppa
  sudo "$debconf_fix" apt-fast install -f -y libargon2-dev libmagickwand-dev libpq-dev libfreetype6-dev libicu-dev libjpeg-dev libpng-dev libonig-dev libxslt1-dev libaspell-dev libcurl4-gnutls-dev libenchant-dev libc-client2007e-dev libkrb5-dev libldap-dev liblz4-dev librabbitmq-dev libsodium-dev libtidy-dev libwebp-dev libxpm-dev libzip-dev libzstd-dev
}

github_deps() {
  if [ "$VERSION_ID" = "16.04" ]; then
    sudo "$debconf_fix" apt-fast install -y --no-upgrade libwebp[0-9]
  elif [ "$VERSION_ID" = "20.04" ]; then
    add_ppa
    sudo "$debconf_fix" apt-fast install -y --no-upgrade libaspell-dev libenchant-dev libtidy-dev
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
  tar_file=php_"$version"%2Bubuntu"$VERSION_ID".tar.zst
  get "/tmp/$tar_file" "https://github.com/shivammathur/php-builder/releases/latest/download/$tar_file" "https://dl.bintray.com/shivammathur/php/$tar_file"
  sudo mkdir -m 777 -p /etc/php/"$version" /usr/local/php /lib/systemd/system /etc/apache2/mods-available /etc/apache2/conf-available /usr/lib/apache2/modules
  wait "$to_wait"
  sudo tar -I zstd -xf "/tmp/$tar_file" -C /usr/local/php
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
  sudo service php"$version"-fpm start
}

runner=${1:-local}
version=${2:-8.0}
debconf_fix="DEBIAN_FRONTEND=noninteractive"
install_dir="/usr/local/php/$version"
pecl_file="$install_dir/etc/conf.d/99-pecl.ini"
. /etc/os-release
install "$runner"
link_prefix
switch_version
configure
