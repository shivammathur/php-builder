. /etc/os-release
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https curl git gnupg jq software-properties-common sudo systemd wget
mysql='mysql-server'
if [ "$ID" = "debian" ]; then
  mysql=default-"$mysql"
  curl -o /etc/apt/trusted.gpg.d/php.gpg -sL https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/ondrej.list
  echo "deb http://deb.debian.org/debian testing main" > /etc/apt/sources.list.d/testing.list
elif [ "$ID" = "ubuntu" ]; then
  apt-add-repository ppa:ubuntu-toolchain-r/test -y
  if [ "$VERSION_ID" = "16.04" ]; then
    LC_ALL=C.UTF-8 apt-add-repository --remove ppa:ondrej/php -y || true
    LC_ALL=C.UTF-8 apt-add-repository http://setup-php.com/ondrej/php/ubuntu -y
    apt-key adv --keyserver keyserver.ubuntu.com --recv 4f4ea0aae5267a6c
  else
    LC_ALL=C.UTF-8 apt-add-repository ppa:ondrej/php -y
  fi
fi

if [ "$VERSION_ID" = "16.04" ] || [ "$VERSION_ID" = "9" ]; then
  libs=("libgccjit-6-dev" "libenchant-dev")
elif [ "$VERSION_ID" = "18.04" ] || [ "$VERSION_ID" = "10" ]; then
  libs=("libgccjit-8-dev" "libenchant-dev")
elif [ "$VERSION_ID" = "20.04" ] || [ "$VERSION_ID" = "11" ]; then
  libs=("libgccjit-10-dev" "libenchant-2-dev")
fi

apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y autoconf gcc-9 g++-9 expect libaio1 locales re2c "$mysql" postgresql pkg-config apache2 apache2-dev libapache2-mod-fcgid libaspell-dev libbz2-dev libbison-dev libedit-dev libcurl4-gnutls-dev libffi-dev libfreetype6-dev "${libs[@]}" libargon2-dev libmagickwand-dev libgmp-dev libicu-dev libjpeg-dev libwebp-dev libc-client2007e-dev libkrb5-dev libldb-dev libldap-dev liblz4-dev libonig-dev libmcrypt-dev libmemcached-dev libpng-dev libpq5 libpq-dev librabbitmq-dev libreadline-dev libpspell-dev libsasl2-dev libsnmp-dev libssl-dev libsqlite3-dev libsodium-dev libtidy-dev libwebp-dev libxml2-dev libxpm-dev libxslt1-dev libzip-dev libzstd-dev zlib1g liblzma-dev liblz4-dev unixodbc-dev
ln -sf /usr/lib/libc-client.so.2007e.0 /usr/lib/x86_64-linux-gnu/libc-client.a
mkdir -p /usr/c-client/
ln -sf /usr/lib/libc-client.so.2007e.0 /usr/c-client/libc-client.a
if [ "$VERSION_ID" = "20.04" ] || [ "$VERSION_ID" = "11" ]; then
  mkdir -p /usr/lib64
  ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib64/libldap.so
  ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib64/liblber.so
fi
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 9
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 9

mkdir -p /opt/zstd
ZSTD_DIR=zstd-$(curl -sL https://github.com/facebook/zstd/releases/latest | grep -Po "tree/v(\d+\.\d+\.\d+)" | cut -d'v' -f 2 | head -n 1)
curl -o /tmp/zstd.tar.gz -sL https://github.com/facebook/zstd/releases/latest/download/"$ZSTD_DIR".tar.gz
tar -xzf /tmp/zstd.tar.gz -C /tmp
(
  cd /tmp/"$ZSTD_DIR" || exit 1
  make install -j"$(nproc)" PREFIX=/opt/zstd
)
ln -sf /opt/zstd/bin/* /usr/local/bin
rm -rf /tmp/zstd*