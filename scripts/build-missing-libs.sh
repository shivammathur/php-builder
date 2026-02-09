#!/usr/bin/env bash
# Build missing static libraries for PHP extensions
set -e

export DEBIAN_FRONTEND=noninteractive
export STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
export JOBS=$(nproc)

echo "=== Building missing static libraries ==="

# Build OpenLDAP
build_openldap() {
    echo "::group::Building OpenLDAP"
    cd /tmp
    rm -rf openldap* build-openldap
    mkdir -p build-openldap && cd build-openldap
    curl -fsSL "https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.6.8.tgz" -o openldap.tgz
    tar xzf openldap.tgz && cd openldap-*

    export CFLAGS="-fPIC -Wno-date-time -I$STATIC_PREFIX/include"
    export CPPFLAGS="-I$STATIC_PREFIX/include"
    export LDFLAGS="-L$STATIC_PREFIX/lib"
    export LIBS="-lssl -lcrypto -lz -ldl -lpthread"
    export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig"
    
    # Patch configure for static linking
    sed -i "s/-lssl -lcrypto/-lssl -lcrypto -lz -ldl -lpthread -lm -lresolv -lutil/g" configure

    # Force C preprocessor to use our includes
    export CC="cc"
    export CPP="cc -E -I$STATIC_PREFIX/include"

    ./configure --prefix="$STATIC_PREFIX" \
      --enable-static --disable-shared --disable-slapd \
      --without-systemd --without-cyrus-sasl --with-tls=openssl \
      CPPFLAGS="-I$STATIC_PREFIX/include" \
      LDFLAGS="-L$STATIC_PREFIX/lib" \
      ac_cv_func_pthread_kill_other_threads_np=no \
      ac_cv_func_ssl_ctx_set_ciphersuites=yes

    sed -i "s/SUBDIRS= include libraries clients servers tests doc/SUBDIRS= include libraries clients servers/" Makefile
    make depend
    make -j"$JOBS"
    make install
    rm -f "$STATIC_PREFIX/lib"/libldap*.so* "$STATIC_PREFIX/lib"/liblber*.so* 2>/dev/null || true

    # Create pkg-config file
    mkdir -p "$STATIC_PREFIX/lib/pkgconfig"
    cat > "$STATIC_PREFIX/lib/pkgconfig/ldap.pc" << 'PKGEOF'
prefix=/opt/static
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: OpenLDAP
Description: OpenLDAP client library
Version: 2.6.8
Libs: -L${libdir} -lldap -llber
Cflags: -I${includedir}
PKGEOF

    cd /tmp && rm -rf build-openldap
    echo "::endgroup::"
    echo "OpenLDAP installed:"
    ls -la "$STATIC_PREFIX/lib"/libldap* "$STATIC_PREFIX/lib"/liblber* 2>/dev/null || true
}

# Build Net-SNMP
build_netsnmp() {
    echo "::group::Building Net-SNMP"
    cd /tmp
    rm -rf net-snmp* build-netsnmp
    mkdir -p build-netsnmp && cd build-netsnmp
    curl -fsSL "https://downloads.sourceforge.net/project/net-snmp/net-snmp/5.9.4/net-snmp-5.9.4.tar.gz" -o netsnmp.tgz
    tar xzf netsnmp.tgz && cd net-snmp-*

    export CFLAGS="-fPIC -I$STATIC_PREFIX/include"
    export CPPFLAGS="-I$STATIC_PREFIX/include"
    export LDFLAGS="-L$STATIC_PREFIX/lib"
    export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig"
    
    # Build without OpenSSL for now (configure doesn't support OpenSSL 3.x well)
    ./configure --prefix="$STATIC_PREFIX" \
      --enable-static --disable-shared --with-defaults \
      --disable-agent --disable-applications --disable-manuals \
      --disable-scripts --disable-mibs --disable-mib-loading \
      --disable-debugging --disable-deprecated --disable-embedded-perl \
      --without-perl-modules --without-openssl \
      --with-transports="Callback,Unix,UDP,TCP" \
      --with-security-modules=usm --with-out-mib-modules="" --enable-ipv6
    
    make -j"$JOBS"
    make install
    rm -f "$STATIC_PREFIX/lib"/libnetsnmp*.so* 2>/dev/null || true

    # Create pkg-config file
    mkdir -p "$STATIC_PREFIX/lib/pkgconfig"
    cat > "$STATIC_PREFIX/lib/pkgconfig/netsnmp.pc" << 'PKGEOF'
prefix=/opt/static
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/net-snmp
Name: netsnmp
Description: Net-SNMP library
Version: 5.9.4
Libs: -L${libdir} -lnetsnmp
Cflags: -I${includedir}
PKGEOF

    cd /tmp && rm -rf build-netsnmp
    echo "::endgroup::"
    echo "Net-SNMP installed:"
    ls -la "$STATIC_PREFIX/lib"/libnetsnmp* 2>/dev/null || true
}

# Check what's already installed
echo "Checking existing libraries..."

if [ ! -f "$STATIC_PREFIX/lib/libldap.a" ]; then
    echo "Building OpenLDAP..."
    build_openldap
else
    echo "OpenLDAP already installed"
fi

if [ ! -f "$STATIC_PREFIX/lib/libnetsnmp.a" ]; then
    echo "Building Net-SNMP..."
    build_netsnmp
else
    echo "Net-SNMP already installed"
fi

echo ""
echo "=== Library installation complete ==="
ls -la "$STATIC_PREFIX/lib"/libldap* "$STATIC_PREFIX/lib"/liblber* "$STATIC_PREFIX/lib"/libnetsnmp* 2>/dev/null || true
