debconf_fix="DEBIAN_FRONTEND=noninteractive"
. /etc/os-release
if ! apt-cache policy | grep -q ondrej/php; then
  LC_ALL=C.UTF-8 sudo apt-add-repository ppa:ondrej/php -y || true
fi
IFS=' ' read -r -a libs <<<"${libs:?}"
sudo "$debconf_fix" apt-get update || true
sudo "$debconf_fix" apt-fast -y install gcc-7 g++-7 expect locales language-pack-de re2c mysql-server postgresql pkg-config apache2 apache2-dev libapache2-mod-fcgid libaspell-dev libbz2-dev libbison-dev libedit-dev libcurl4-gnutls-dev libffi-dev libfreetype6-dev "${libs[@]}" libargon2-dev libmagickwand-dev libgmp-dev libicu-dev libjpeg-dev libwebp-dev libc-client2007e-dev libkrb5-dev libldb-dev libldap-dev liblz4-dev libonig-dev libmcrypt-dev libmemcached-dev libpng-dev libpq5 libpq-dev librabbitmq-dev libreadline-dev libpspell-dev libsasl2-dev libsnmp-dev libssl-dev libsqlite3-dev libsodium-dev libtidy-dev libwebp-dev libxml2-dev libxpm-dev libxslt1-dev libzip-dev libzstd-dev
sudo ln -sf /usr/lib/libc-client.so.2007e.0 /usr/lib/x86_64-linux-gnu/libc-client.a
sudo mkdir -p /usr/c-client/
sudo ln -sf /usr/lib/libc-client.so.2007e.0 /usr/c-client/libc-client.a
if [ "$VERSION_ID" = "20.04" ]; then
  sudo ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib64/libldap.so
  sudo ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib64/liblber.so
fi
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 7
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 7