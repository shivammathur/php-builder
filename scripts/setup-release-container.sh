#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq curl xz-utils ca-certificates \
  libxml2 libssl3 libcurl4 libpng16-16 libjpeg8 libfreetype6 libonig5 libsodium23 \
  libargon2-1 libzip4 libpq5 libgmp10 libreadline8 libffi8 libedit2 libavif16 \
  libwebp7 libxpm4 libenchant-2-2 libtidy5deb1 libxslt1.1 liblmdb0 libqdbm14 \
  libc-client2007e libsnmp40 libldap-common libbz2-1.0 \
  libgomp1 unixodbc firebird3.0-utils libsqlite3-0 libyaml-0-2 libzmq5 \
  libmemcached11 libmemcachedutil2 libmagickwand-6.q16-7 freetds-dev

# Download and extract release
curl -sL "https://github.com/shivammathur/php-builder/releases/download/8.5/php_8.5+ubuntu24.04.tar.xz" -o /tmp/php.tar.xz
cd / && tar -xf /tmp/php.tar.xz

# Create symlinks
ln -sf /usr/bin/php8.5 /php
ln -sf /usr/bin/php-cgi8.5 /php-cgi
ln -sf /usr/bin/phpdbg8.5 /phpdbg
ln -sf /usr/sbin/php-fpm8.5 /php-fpm

echo "=== Release PHP installed ==="
/php -v 2>&1 | head -3
echo "Module count: $(/php -m 2>/dev/null | wc -l)"
