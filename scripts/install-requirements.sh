#!/usr/bin/env bash

# Function to cURL.
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

# Helper function to update the package list(s).
update_lists_helper() {
  list=$1
  if [[ -n "$list" ]]; then
    apt-get update -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
  else
    apt-get update
  fi
}

# Function to update the package list(s).
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

# Function to get the fingerprint from a Ubuntu repository.
ubuntu_fingerprint() {
  ppa="$1"
  ppa_uri="~${ppa%/*}/+archive/ubuntu/${ppa##*/}"
  get -s "" "${lp_api[0]}/$ppa_uri" | jq -er '.signing_key_fingerprint' 2>/dev/null \
  || get -s "" "${lp_api[1]}/$ppa_uri" | jq -er '.signing_key_fingerprint' 2>/dev/null \
  || get -s "" "$ppa_sp/keys/$ppa.fingerprint"
}

# Function to get the fingerprint from a Debian repository.
debian_fingerprint() {
  ppa=$1
  ppa_url=$2
  package_dist=$3
  release_pub=/tmp/"${ppa/\//-}".gpg
  get -q "$release_pub" "$ppa_url"/dists/"$package_dist"/Release.gpg
  gpg --homedir /tmp --list-packets "$release_pub" | grep -Eo 'fpr\sv4\s.*[a-zA-Z0-9]+' | head -n 1 | cut -d ' ' -f 3
}

# Function to add the keyring for a repository.
add_key() {
  ppa=${1:-ondrej/php}
  ppa_url=$2
  package_dist=$3
  key_source=$4
  key_file=$5
  key_urls=("$key_source")
  if [[ "$key_source" =~ launchpad.net|launchpadcontent.net|debian.org|setup-php.com ]]; then
    fingerprint="$("${ID}"_fingerprint "$ppa" "$ppa_url" "$package_dist")"
    sks_params="op=get&options=mr&exact=on&search=0x$fingerprint"
    key_urls=("${sks[@]/%/\/pks\/lookup\?"$sks_params"}")
  fi
  key_urls+=("$ppa_sp/keys/$ppa.gpg")
  [ ! -e "$key_source" ] && get -q "$key_file" "${key_urls[@]}"
  if [[ "$(file "$key_file")" =~ .*('Public-Key (old)'|'Secret-Key') ]]; then
    gpg --homedir /tmp --batch --yes --dearmor "$key_file" && rm -f "$key_file" >/dev/null 2>&1
    mv "$key_file".gpg "$key_file"
  fi
}

# Function to add a package list.
add_list() {
  ppa=${1-ondrej/php}
  ppa_url=${2:-"$lpc_ppa/$ppa/ubuntu"}
  key_source=${3:-"$ppa_url"}
  package_dist=${4:-"$VERSION_CODENAME"}
  branches=${5:-main}
  ppa_search="deb .*$ppa_url $package_dist .*$branches"
  grep -Eqr "$ppa_search" "$list_dir" && echo "Repository $ppa already exists" && return
  arch=$(dpkg --print-architecture)
  [ -e "$key_source" ] && key_file=$key_source || key_file="$key_dir"/"${ppa/\//-}"-keyring.gpg
  add_key "$ppa" "$ppa_url" "$package_dist" "$key_source" "$key_file"
  echo "deb [arch=$arch signed-by=$key_file] $ppa_url $package_dist $branches" | tee "$list_dir"/"${ppa/\//-}".list >/dev/null 2>&1
  update_lists "$ppa" "$ppa_search"
}

# Function to remove a package list.
remove_list() {
  ppa=${1-ondrej/php}
  [ -n "$2" ] && ppa_urls=("$2") || ppa_urls=("$lp_ppa/$ppa/ubuntu" "$lpc_ppa/$ppa/ubuntu")
  for ppa_url in "${ppa_urls[@]}"; do
    grep -lr "$ppa_url" "$list_dir" | xargs -n1 sudo rm -f
  done
  sudo rm -f "$key_dir"/"${ppa/\//-}"-keyring || true
}

# Function to add a package repository.
add_ppa() {
  if [ "$ID" = "ubuntu" ]; then
    add_list ondrej/php
  elif [ "$ID" = "debian" ]; then
    add_list ondrej/php https://packages.sury.org/php/ https://packages.sury.org/php/apt.gpg
  fi
}

# Function to install packages.
install_packages() {
  packages=("$@")
  apt_mgr='apt-get'
  command -v apt-fast >/dev/null && apt_mgr='apt-fast'
  apt_install="$apt_mgr install -yq --no-install-recommends"
  $apt_install "${packages[@]}" 2>/dev/null || (update_lists && $apt_install "${packages[@]}")
}

# Function to configure the build requirements for PHP.
configure_requirements() {
  ln -sf /usr/lib/libc-client.so.2007e.0 /usr/lib/x86_64-linux-gnu/libc-client.a
  mkdir -p /usr/c-client/ /usr
  ln -sf /usr/lib/libc-client.so.2007e.0 /usr/c-client/libc-client.a
  ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so
  ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib/liblber.so
  ln -s /usr/include/x86_64-linux-gnu/curl /usr/include/curl
  ln -s /usr/include/x86_64-linux-gnu/gmp.h /usr/include/gmp.h
  if [ -d /usr/lib64 ]; then
    ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib64/libldap.so
    ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib64/liblber.so
  fi
}

# Function to get mysql package.
get_libmysql() {
  mysql='libmysqlclient-dev'
  if [ "$ID" = "debian" ]; then
    mysql=default-"$mysql"
  fi
  echo "$mysql"
}

if [ -z "${BUILD}" ]; then
  echo "BUILD is not defined"
  exit 1;
fi

# Constants.
list_dir='/etc/apt/sources.list.d'
list_file="$list_dir/ubuntu.sources"
[ -e "$list_file" ] || list_file='/etc/apt/sources.list'
lp_api=(
  'https://api.launchpad.net/1.0'
  'https://api.launchpad.net/devel'
)
lp_ppa='http://ppa.launchpad.net'
lpc_ppa='https://ppa.launchpadcontent.net'
key_dir='/usr/share/keyrings'
ppa_sp='https://ppa.setup-php.com'
sks=(
  'https://keyserver.ubuntu.com'
  'https://pgp.mit.edu'
  'https://keys.openpgp.org'
)

# Add OS information to the environment.
. /etc/os-release

# Set frontend to noninteractive
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

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

# Set library versions
libmysql_dev=$(get_libmysql)
libenchant_dev=$(apt-cache show libenchant-?[0-9]+?-dev | grep 'Package' | head -n 1 | cut -d ' ' -f 2)
[[ "$PHP_VERSION" =~ 5.6|7.[0-2] ]] && libpcre_dev=libpcre3-dev || libpcre_dev=libpcre2-dev
gcc_version=$(gcc --version | grep -Po '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | cut -d '.' -f 1)
libgcc_dev="libgcc-$gcc_version-dev"
libgccjit_dev="libgccjit-$gcc_version-dev"

# Add required package repositories.
add_ppa
if [ "${BUILD:?}" = "debug" ]; then
  sed -i "h;s/^//;p;x" /etc/apt/sources.list.d/ondrej-*.list
  sed -i '2s/main$/main\/debug/' /etc/apt/sources.list.d/ondrej-*.list
  apt-get update
fi
add_list github/cli https://cli.github.com/packages https://cli.github.com/packages/githubcli-archive-keyring.gpg stable

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
                 libbz2-dev \
                 libc-client2007e-dev \
                 libcurl4-openssl-dev \
                 libdb-dev \
                 libedit-dev \
                 "$libenchant_dev" \
                 libevent-dev \
                 libexpat1-dev \
                 libffi-dev \
                 libfreetype6-dev \
                 libraqm-dev \
                 libimagequant-dev \
                 "$libgcc_dev" \
                 "$libgccjit_dev" \
                 libgcrypt20-dev \
                 libgd-dev \
                 libglib2.0-dev \
                 libgmp3-dev \
                 libicu-dev \
                 libjpeg-dev \
                 libkrb5-dev \
                 libldb-dev \
                 libldap2-dev \
                 liblmdb-dev \
                 liblz4-dev \
                 liblzma-dev \
                 libmagic-dev \
                 libmagickwand-dev \
                 libmcrypt-dev \
                 libmemcached-dev \
                 libmhash-dev \
                 "$libmysql_dev" \
                 libnss-myhostname \
                 libonig-dev \
                 libonig-dev \
                 libpam0g-dev \
                 "$libpcre_dev" \
                 libpng-dev \
                 libpq-dev \
                 libpspell-dev \
                 libqdbm-dev \
                 librabbitmq-dev \
                 libreadline-dev \
                 libsasl2-dev \
                 libsnmp-dev \
                 libsodium-dev \
                 libsqlite3-dev \
                 libssl-dev \
                 libsystemd-dev \
                 libtidy-dev \
                 libtool \
                 libwebp-dev \
                 libwrap0-dev \
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
                 pkg-config \
                 re2c \
                 shtool \
                 systemtap-sdt-dev \
                 tzdata \
                 unixodbc-dev \
                 zlib1g-dev

# Configure PHP build requirements.
configure_requirements
