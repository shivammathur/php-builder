#!/bin/bash
# Build remaining static libraries for PHP extensions
# This script builds: PostgreSQL, OpenLDAP, net-snmp, glib, enchant, unixODBC, FreeTDS
set -e

STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
BUILD_DIR="/tmp/static-libs-build"
NPROC=$(nproc)

export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
export CFLAGS="-O2 -fPIC -I$STATIC_PREFIX/include"
export CPPFLAGS="-I$STATIC_PREFIX/include"
export LDFLAGS="-L$STATIC_PREFIX/lib -L$STATIC_PREFIX/lib64"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Install build dependencies
echo "=== Installing build dependencies ==="
apt-get update -qq
apt-get install -y -qq flex bison autoconf automake libtool gettext pkg-config \
  python3 python3-dev meson ninja-build cmake

build_postgresql() {
  echo ""
  echo "==========================================="
  echo "Building PostgreSQL (libpq) without GSSAPI"
  echo "==========================================="
  
  local VERSION="16.2"
  if [ -f "$STATIC_PREFIX/lib/libpq.a" ]; then
    echo "libpq already exists, skipping..."
    return 0
  fi
  
  wget -q "https://ftp.postgresql.org/pub/source/v${VERSION}/postgresql-${VERSION}.tar.gz"
  tar xzf "postgresql-${VERSION}.tar.gz"
  cd "postgresql-${VERSION}"
  
  ./configure \
    --prefix="$STATIC_PREFIX" \
    --with-ssl=openssl \
    --without-gssapi \
    --without-ldap \
    --without-pam \
    --without-readline \
    --without-systemd \
    --without-icu \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"
  
  # Build only libpq and required components
  make -C src/common -j$NPROC
  make -C src/port -j$NPROC
  make -C src/interfaces/libpq -j$NPROC
  make -C src/bin/pg_config -j$NPROC
  
  # Install
  make -C src/common install
  make -C src/port install
  make -C src/interfaces/libpq install
  make -C src/bin/pg_config install
  make -C src/include install
  
  cd "$BUILD_DIR"
  rm -rf "postgresql-${VERSION}"
  
  echo "PostgreSQL libpq built successfully!"
  ls -la "$STATIC_PREFIX/lib/libpq.a"
}

build_openldap() {
  echo ""
  echo "==========================================="
  echo "Building OpenLDAP with OpenSSL (no GnuTLS)"
  echo "==========================================="
  
  local VERSION="2.6.7"
  if [ -f "$STATIC_PREFIX/lib/libldap.a" ]; then
    echo "libldap already exists, checking for GnuTLS..."
    if nm "$STATIC_PREFIX/lib/libldap.a" | grep -qi gnutls; then
      echo "Existing libldap has GnuTLS, rebuilding..."
    else
      echo "libldap looks clean, skipping..."
      return 0
    fi
  fi
  
  wget -q "https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-${VERSION}.tgz"
  tar xzf "openldap-${VERSION}.tgz"
  cd "openldap-${VERSION}"
  
  ./configure \
    --prefix="$STATIC_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-slapd \
    --disable-slurpd \
    --disable-relay \
    --disable-bdb \
    --disable-hdb \
    --disable-mdb \
    --disable-overlays \
    --without-cyrus-sasl \
    --with-tls=openssl \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="-lssl -lcrypto -lpthread -ldl"
  
  make -j$NPROC depend
  make -j$NPROC
  make install
  
  cd "$BUILD_DIR"
  rm -rf "openldap-${VERSION}"
  
  echo "OpenLDAP built successfully!"
  ls -la "$STATIC_PREFIX/lib/libldap.a"
}

build_netsnmp() {
  echo ""
  echo "==========================================="
  echo "Building net-snmp for ARM64"
  echo "==========================================="
  
  local VERSION="5.9.4"
  if [ -f "$STATIC_PREFIX/lib/libnetsnmp.a" ]; then
    echo "libnetsnmp already exists, skipping..."
    return 0
  fi
  
  wget -q "https://sourceforge.net/projects/net-snmp/files/net-snmp/${VERSION}/net-snmp-${VERSION}.tar.gz/download" -O "net-snmp-${VERSION}.tar.gz"
  tar xzf "net-snmp-${VERSION}.tar.gz"
  cd "net-snmp-${VERSION}"
  
  ./configure \
    --prefix="$STATIC_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-embedded-perl \
    --disable-perl-cc-checks \
    --without-perl-modules \
    --disable-agent \
    --disable-applications \
    --disable-scripts \
    --disable-mibs \
    --disable-mib-loading \
    --with-openssl="$STATIC_PREFIX" \
    --without-rpm \
    --without-pcre \
    --with-defaults \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"
  
  make -j$NPROC
  make install
  
  cd "$BUILD_DIR"
  rm -rf "net-snmp-${VERSION}"
  
  echo "net-snmp built successfully!"
  ls -la "$STATIC_PREFIX/lib/libnetsnmp.a"
}

build_glib() {
  echo ""
  echo "==========================================="
  echo "Building GLib (for enchant)"
  echo "==========================================="
  
  local VERSION="2.78.4"
  if [ -f "$STATIC_PREFIX/lib/libglib-2.0.a" ]; then
    echo "libglib already exists, skipping..."
    return 0
  fi
  
  # GLib requires pcre2
  if [ ! -f "$STATIC_PREFIX/lib/libpcre2-8.a" ]; then
    echo "Building PCRE2 first..."
    wget -q "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz"
    tar xzf pcre2-10.42.tar.gz
    cd pcre2-10.42
    ./configure --prefix="$STATIC_PREFIX" --enable-static --disable-shared
    make -j$NPROC && make install
    cd "$BUILD_DIR"
    rm -rf pcre2-10.42
  fi
  
  wget -q "https://download.gnome.org/sources/glib/2.78/glib-${VERSION}.tar.xz"
  tar xf "glib-${VERSION}.tar.xz"
  cd "glib-${VERSION}"
  
  # GLib uses meson
  meson setup _build \
    --prefix="$STATIC_PREFIX" \
    --default-library=static \
    --buildtype=release \
    -Dtests=false \
    -Dinstalled_tests=false \
    -Dlibmount=disabled \
    -Dselinux=disabled \
    -Dxattr=false \
    -Dlibelf=disabled \
    -Dsysprof=disabled
  
  ninja -C _build
  ninja -C _build install
  
  cd "$BUILD_DIR"
  rm -rf "glib-${VERSION}"
  
  echo "GLib built successfully!"
  ls -la "$STATIC_PREFIX/lib/libglib-2.0.a"
}

build_enchant() {
  echo ""
  echo "==========================================="
  echo "Building Enchant"
  echo "==========================================="
  
  local VERSION="2.6.7"
  if [ -f "$STATIC_PREFIX/lib/libenchant-2.a" ]; then
    echo "libenchant already exists, skipping..."
    return 0
  fi
  
  # Build hunspell first
  if [ ! -f "$STATIC_PREFIX/lib/libhunspell-1.7.a" ]; then
    echo "Building Hunspell first..."
    wget -q "https://github.com/hunspell/hunspell/releases/download/v1.7.2/hunspell-1.7.2.tar.gz"
    tar xzf hunspell-1.7.2.tar.gz
    cd hunspell-1.7.2
    ./configure --prefix="$STATIC_PREFIX" --enable-static --disable-shared
    make -j$NPROC && make install
    cd "$BUILD_DIR"
    rm -rf hunspell-1.7.2
  fi
  
  wget -q "https://github.com/AbiWord/enchant/releases/download/v${VERSION}/enchant-${VERSION}.tar.gz"
  tar xzf "enchant-${VERSION}.tar.gz"
  cd "enchant-${VERSION}"
  
  # Need to tell enchant where glib is
  export GLIB_CFLAGS="-I$STATIC_PREFIX/include/glib-2.0 -I$STATIC_PREFIX/lib/glib-2.0/include"
  export GLIB_LIBS="-L$STATIC_PREFIX/lib -lglib-2.0 -lgthread-2.0 -lgmodule-2.0 -lpcre2-8 -lpthread"
  
  ./configure \
    --prefix="$STATIC_PREFIX" \
    --enable-static \
    --disable-shared \
    --with-hunspell \
    --without-aspell \
    --without-hspell \
    --without-voikko \
    --without-applespell \
    --without-zemberek \
    CFLAGS="$CFLAGS $GLIB_CFLAGS" \
    CXXFLAGS="$CFLAGS $GLIB_CFLAGS" \
    LDFLAGS="$LDFLAGS $GLIB_LIBS"
  
  make -j$NPROC
  make install
  
  cd "$BUILD_DIR"
  rm -rf "enchant-${VERSION}"
  
  echo "Enchant built successfully!"
  ls -la "$STATIC_PREFIX/lib/libenchant-2.a" 2>/dev/null || ls -la "$STATIC_PREFIX/lib/libenchant*.a"
}

build_unixodbc() {
  echo ""
  echo "==========================================="
  echo "Building unixODBC"
  echo "==========================================="
  
  local VERSION="2.3.12"
  if [ -f "$STATIC_PREFIX/lib/libodbc.a" ]; then
    echo "libodbc already exists, skipping..."
    return 0
  fi
  
  wget -q "https://www.unixodbc.org/unixODBC-${VERSION}.tar.gz"
  tar xzf "unixODBC-${VERSION}.tar.gz"
  cd "unixODBC-${VERSION}"
  
  ./configure \
    --prefix="$STATIC_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-gui \
    --disable-drivers \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"
  
  make -j$NPROC
  make install
  
  cd "$BUILD_DIR"
  rm -rf "unixODBC-${VERSION}"
  
  echo "unixODBC built successfully!"
  ls -la "$STATIC_PREFIX/lib/libodbc.a"
}

build_freetds() {
  echo ""
  echo "==========================================="
  echo "Building FreeTDS (for pdo_dblib)"
  echo "==========================================="
  
  local VERSION="1.4.10"
  if [ -f "$STATIC_PREFIX/lib/libsybdb.a" ]; then
    echo "libsybdb already exists, skipping..."
    return 0
  fi
  
  wget -q "https://www.freetds.org/files/stable/freetds-${VERSION}.tar.gz"
  tar xzf "freetds-${VERSION}.tar.gz"
  cd "freetds-${VERSION}"
  
  ./configure \
    --prefix="$STATIC_PREFIX" \
    --enable-static \
    --disable-shared \
    --with-openssl="$STATIC_PREFIX" \
    --disable-odbc \
    --disable-apps \
    --disable-pool \
    --enable-msdblib \
    --enable-sybase-compat \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"
  
  make -j$NPROC
  make install
  
  cd "$BUILD_DIR"
  rm -rf "freetds-${VERSION}"
  
  echo "FreeTDS built successfully!"
  ls -la "$STATIC_PREFIX/lib/libsybdb.a"
}

# Main: Build all libraries
main() {
  echo "Building remaining static libraries for PHP extensions"
  echo "Static prefix: $STATIC_PREFIX"
  echo "Build dir: $BUILD_DIR"
  echo ""
  
  build_postgresql
  build_openldap
  build_netsnmp
  build_unixodbc
  build_freetds
  # GLib and enchant are complex, build last
  build_glib
  build_enchant
  
  echo ""
  echo "==========================================="
  echo "All static libraries built successfully!"
  echo "==========================================="
  echo ""
  echo "Libraries available:"
  ls -la "$STATIC_PREFIX/lib/"*.a | grep -E '(pq|ldap|lber|snmp|odbc|sybdb|glib|enchant)' || true
}

# Run specific library if argument given, otherwise build all
if [ -n "$1" ]; then
  case "$1" in
    postgresql|pgsql) build_postgresql ;;
    openldap|ldap) build_openldap ;;
    netsnmp|snmp) build_netsnmp ;;
    glib) build_glib ;;
    enchant) build_enchant ;;
    unixodbc|odbc) build_unixodbc ;;
    freetds|dblib) build_freetds ;;
    *) echo "Unknown library: $1"; exit 1 ;;
  esac
else
  main
fi
