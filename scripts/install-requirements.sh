#!/usr/bin/env bash
set -e

# Function to install packages.
install_packages() {
  packages=("$@")
  apt_mgr='apt-get'
  command -v apt-fast >/dev/null && apt_mgr='apt-fast'
  apt_install="$apt_mgr install -yq --no-install-recommends"
  for attempt in {1..3}; do
    if $apt_install "${packages[@]}" 2>/dev/null; then
      return 0
    fi
    apt-get clean
    apt-get update
    sleep "$((attempt * 5))"
  done
  $apt_install "${packages[@]}"
}

ensure_github_cli_candidate() {
  local arch key_file list_file

  apt-cache show gh >/dev/null 2>&1 && return 0

  arch=$(dpkg --print-architecture)
  key_file=/usr/share/keyrings/githubcli-archive-keyring.gpg
  list_file=/etc/apt/sources.list.d/github-cli.list
  install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
  curl --retry 5 --retry-all-errors -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$key_file"
  chmod go+r "$key_file"
  printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' "$arch" "$key_file" > "$list_file"
  apt-get update
}

# Function to configure the build requirements for PHP.
configure_requirements() {
  multiarch=$(dpkg-architecture -q DEB_HOST_MULTIARCH)
  mkdir -p /usr/c-client/ /usr/lib/"$multiarch"
  [ -e /usr/lib/libc-client.so.2007e.0 ] && ln -sf /usr/lib/libc-client.so.2007e.0 /usr/lib/"$multiarch"/libc-client.a
  [ -e /usr/lib/libc-client.so.2007e.0 ] && ln -sf /usr/lib/libc-client.so.2007e.0 /usr/c-client/libc-client.a
  [ -e /usr/lib/"$multiarch"/libldap.so ] && ln -sf /usr/lib/"$multiarch"/libldap.so /usr/lib/libldap.so
  [ -e /usr/lib/"$multiarch"/liblber.so ] && ln -sf /usr/lib/"$multiarch"/liblber.so /usr/lib/liblber.so
  [ -e /usr/include/"$multiarch"/curl ] && ln -sfn /usr/include/"$multiarch"/curl /usr/include/curl
  [ -e /usr/include/"$multiarch"/gmp.h ] && ln -sfn /usr/include/"$multiarch"/gmp.h /usr/include/gmp.h
  if [ -d /usr/lib64 ]; then
    [ -e /usr/lib/"$multiarch"/libldap.so ] && ln -sf /usr/lib/"$multiarch"/libldap.so /usr/lib64/libldap.so
    [ -e /usr/lib/"$multiarch"/liblber.so ] && ln -sf /usr/lib/"$multiarch"/liblber.so /usr/lib64/liblber.so
  fi
  return 0
}

# Function to get mysql package.
get_libmysql() {
  mysql='libmysqlclient-dev'
  if [ "$ID" = "debian" ]; then
    mysql=default-"$mysql"
  fi
  echo "$mysql"
}

if [ -z "${BUILD:-}" ]; then
  echo "BUILD is not defined"
  exit 1;
fi
if [ -z "${PHP_VERSION:-}" ]; then
  echo "PHP_VERSION is not defined"
  exit 1;
fi

# Add OS information to the environment.
. /etc/os-release
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Set frontend to noninteractive
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Update package lists.
apt-get update

# Install the build requirements for PHP
install_packages apt-transport-https \
                 ca-certificates \
                 curl \
                 file \
                 gcc \
                 g++ \
                 git \
                 gnupg \
                 jq \
                 sudo \
                 wget \
                 zstd

ensure_github_cli_candidate

# Set library versions
libmysql_dev=$(get_libmysql)
libenchant_dev=$(apt-cache show libenchant-?[0-9]+?-dev | grep 'Package' | head -n 1 | cut -d ' ' -f 2)
gcc_version=$(gcc --version | grep -Po '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | cut -d '.' -f 1)
libgcc_dev="libgcc-$gcc_version-dev"
libgccjit_dev="libgccjit-$gcc_version-dev"

# Install PHP build requirements.
install_packages apache2 \
                 apache2-dev \
                 autoconf \
                 automake \
                 bison \
                 dpkg-dev \
                 firebird-dev \
                 freetds-dev \
                 gh \
                 libapparmor-dev \
                 libacl1-dev \
                 libaio-dev \
                 libapr1-dev \
                 libargon2-dev \
                 libapache2-mod-fcgid \
                 libaspell-dev \
                 libavif-dev \
                 libbz2-dev \
                 libbrotli-dev \
                 libc-ares-dev \
                 libc6-dev \
                 libcurl4-openssl-dev \
                 libdb-dev \
                 libedit-dev \
                 "$libenchant_dev" \
                 libevent-dev \
                 libexpat1-dev \
                 libffi-dev \
                 libfontconfig-dev \
                 libfreetype6-dev \
                 libraqm-dev \
                 "$libgcc_dev" \
                 "$libgccjit_dev" \
                 libgcrypt20-dev \
                 libgearman-dev \
                 libglib2.0-dev \
                 libgmp3-dev \
                 libgpgme-dev \
                 libgrpc-dev \
                 libheif-dev \
                 libicu-dev \
                 libimagequant-dev \
                 libjpeg-dev \
                 libkrb5-dev \
                 krb5-multidev \
                 libldb-dev \
                 libldap2-dev \
                 liblmdb-dev \
                 liblz4-dev \
                 liblzma-dev \
                 libmagic-dev \
                 libmaxminddb-dev \
                 libnghttp2-dev \
                 libmagickwand-dev \
                 libmcrypt-dev \
                 libmemcached-dev \
                 libmhash-dev \
                 "$libmysql_dev" \
                 libnss-myhostname \
                 libonig-dev \
                 libpam0g-dev \
                 libpng-dev \
                 libpq-dev \
                 libprotobuf-dev \
                 libpspell-dev \
                 libqdbm-dev \
                 librabbitmq-dev \
                 librdkafka-dev \
                 libreadline-dev \
                 librrd-dev \
                 libsasl2-dev \
                 libsmbclient-dev \
                 libsnmp-dev \
                 libsodium-dev \
                 libsqlite3-dev \
                 libssh2-1-dev \
                 libssl-dev \
                 libsystemd-dev \
                 libtidy-dev \
                 libtiff-dev \
                 libtool \
                 libvpx-dev \
                 libwebp-dev \
                 libwrap0-dev \
                 libx11-dev \
                 libxml2-dev \
                 libxmlrpc-epi-dev \
                 libxpm-dev \
                 libxslt1-dev \
                 libyaml-dev \
                 libzip-dev \
                 libzmq3-dev \
                 libzstd-dev \
                 locales-all \
                 netbase \
                 netcat-openbsd \
                 patch \
                 pkg-config \
                 protobuf-compiler \
                 re2c \
                 shtool \
                 systemtap-sdt-dev \
                 tzdata \
                 unixodbc-dev \
                 uuid-dev \
                 zlib1g-dev

# Install locally built library overlays.
bash "$script_dir/lib/install.sh" --php-version "$PHP_VERSION"

# Configure PHP build requirements.
configure_requirements
