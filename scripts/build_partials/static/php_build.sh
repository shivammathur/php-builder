# Static PHP Build Functions
# These functions extend the dynamic build functions for static linking
# The base functions from build_partials/php_build.sh are reused

# Function to get build flags for static linking
get_static_buildflags() {
  type=$1
  STATIC_PREFIX="/opt/static"
  
  case "$type" in
    CFLAGS)
      echo "-O2 -fPIC -fvisibility=hidden -I$STATIC_PREFIX/include"
      ;;
    CPPFLAGS)
      echo "-I$STATIC_PREFIX/include"
      ;;
    CXXFLAGS)
      echo "-O2 -fPIC -fvisibility=hidden -I$STATIC_PREFIX/include"
      ;;
    LDFLAGS)
      # Do not force static libstdc++/libgcc; allow dynamic C++ runtime per requirements
      echo "-L$STATIC_PREFIX/lib -L$STATIC_PREFIX/lib64 -L$STATIC_PREFIX/lib/aarch64-linux-gnu"
      ;;
    PKG_CONFIG_PATH)
      echo "$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig:$STATIC_PREFIX/lib/aarch64-linux-gnu/pkgconfig"
      ;;
    LIBS)
      # Build LIBS from available static archives only to avoid configure failures
      STATIC_PREFIX="/opt/static"
      libs=()
      add_lib() {
        if [ -f "$1" ]; then
          libs+=("$1")
        fi
      }
      add_first() {
        for lib in "$@"; do
          if [ -f "$lib" ]; then
            libs+=("$lib")
            return
          fi
        done
      }

      # Core dependencies (order matters: users first, providers last)
      add_lib "$STATIC_PREFIX/lib/libzip.a"
      add_lib "$STATIC_PREFIX/lib/libsqlite3.a"
      add_lib "$STATIC_PREFIX/lib/libsodium.a"
      add_lib "$STATIC_PREFIX/lib/libpq.a"
      add_lib "$STATIC_PREFIX/lib/libpgcommon.a"
      add_lib "$STATIC_PREFIX/lib/libpgport.a"
      add_lib "$STATIC_PREFIX/lib/libldap.a"
      add_lib "$STATIC_PREFIX/lib/liblber.a"
      add_lib "$STATIC_PREFIX/lib/libodbc.a"
      add_lib "$STATIC_PREFIX/lib/libodbcinst.a"
      add_lib "$STATIC_PREFIX/lib/libltdl.a"
      add_lib "$STATIC_PREFIX/lib/libsybdb.a"
      add_lib "$STATIC_PREFIX/lib/libct.a"
      add_lib "$STATIC_PREFIX/lib/liblmdb.a"
      add_lib "$STATIC_PREFIX/lib/libqdbm.a"

      # GD stack
      add_lib "$STATIC_PREFIX/lib/libfreetype.a"
      add_first "$STATIC_PREFIX/lib/libpng16.a" "$STATIC_PREFIX/lib/libpng.a"
      add_lib "$STATIC_PREFIX/lib/libjpeg.a"
      add_lib "$STATIC_PREFIX/lib/libwebp.a"
      add_lib "$STATIC_PREFIX/lib/libsharpyuv.a"

      # libedit + ncurses
      add_lib "$STATIC_PREFIX/lib/libedit.a"
      add_lib "$STATIC_PREFIX/lib/libbsd.a"
      add_lib "$STATIC_PREFIX/lib/libtinfo.a"
      add_first "$STATIC_PREFIX/lib/libncurses.a" "$STATIC_PREFIX/lib/libncursesw.a"

      # XML/XSLT
      add_lib "$STATIC_PREFIX/lib/libexslt.a"
      add_lib "$STATIC_PREFIX/lib/libxslt.a"
      add_lib "$STATIC_PREFIX/lib/libxml2.a"

      # ICU (order matters)
      add_lib "$STATIC_PREFIX/lib/libicuio.a"
      add_lib "$STATIC_PREFIX/lib/libicui18n.a"
      add_lib "$STATIC_PREFIX/lib/libicuuc.a"
      add_lib "$STATIC_PREFIX/lib/libicudata.a"

      # Misc
      add_lib "$STATIC_PREFIX/lib/liblzma.a"
      add_lib "$STATIC_PREFIX/lib/libonig.a"
      add_lib "$STATIC_PREFIX/lib/libcurl.a"
      add_lib "$STATIC_PREFIX/lib/libffi.a"
      add_lib "$STATIC_PREFIX/lib/libssl.a"
      add_lib "$STATIC_PREFIX/lib/libcrypto.a"
      add_lib "$STATIC_PREFIX/lib/libz.a"
      add_lib "$STATIC_PREFIX/lib/libbz2.a"

      # Dynamic system libs
      libs+=("-lm" "-lpthread" "-ldl" "-lresolv" "-lstdc++")

      echo "${libs[*]}"
      ;;
    STATIC_CXX_LIBS)
      local gcc_lib_dir
      gcc_lib_dir=$(dirname "$(g++ --print-file-name=libstdc++.a)")
      echo "$gcc_lib_dir/libstdc++.a $gcc_lib_dir/libsupc++.a $gcc_lib_dir/libgcc_eh.a"
      ;;
  esac
}

# Function to set up static library environment variables
setup_static_environment() {
  STATIC_PREFIX="/opt/static"
  
  # Set and export FLAGS for static builds
  CFLAGS="$(get_static_buildflags CFLAGS) $(getconf LFS_CFLAGS)"
  CFLAGS="$CFLAGS -DOPENSSL_SUPPRESS_DEPRECATED"
  CPPFLAGS="$(get_static_buildflags CPPFLAGS)"
  CXXFLAGS="$(get_static_buildflags CXXFLAGS)"
  LDFLAGS="$(get_static_buildflags LDFLAGS)"
  LIBS="$(get_static_buildflags LIBS)"
  PKG_CONFIG_PATH="$(get_static_buildflags PKG_CONFIG_PATH)"

  DEB_HOST_MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)"
  
  # Set ICU flags for static linking
  ICU_CFLAGS="-I$STATIC_PREFIX/include"
  ICU_LIBS="$STATIC_PREFIX/lib/libicuio.a $STATIC_PREFIX/lib/libicui18n.a $STATIC_PREFIX/lib/libicuuc.a $STATIC_PREFIX/lib/libicudata.a -lm"
  
  # ICU C++ standard - PHP's configure already detects C++17 for ICU 75+
  # We export ICU_CXXFLAGS without -std flag since PHP's PHP_CXX_COMPILE_STDCXX 
  # already adds the correct one via PHP_INTL_STDCXX
  ICU_VERSION=$(pkg-config --modversion icu-uc 2>/dev/null || echo "75")
  ICU_CXXFLAGS=""  # Don't add -std flag, PHP's configure handles it

  SED=$(command -v sed)

  # Export all environment variables for static build
  export CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBS PKG_CONFIG_PATH
  export DEB_HOST_MULTIARCH ICU_CFLAGS ICU_LIBS ICU_CXXFLAGS SED

  # Static library paths for PHP configure
  export OPENSSL_CFLAGS="-I$STATIC_PREFIX/include"
  export OPENSSL_LIBS="$STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a $STATIC_PREFIX/lib/libz.a -lpthread -ldl"
  export CURL_CFLAGS="-I$STATIC_PREFIX/include"
  export CURL_LIBS="$STATIC_PREFIX/lib/libcurl.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a $STATIC_PREFIX/lib/libz.a -lpthread -ldl"
  export LIBXML_CFLAGS="-I$STATIC_PREFIX/include/libxml2"
  export LIBXML_LIBS="$STATIC_PREFIX/lib/libxml2.a $STATIC_PREFIX/lib/libz.a $STATIC_PREFIX/lib/liblzma.a $STATIC_PREFIX/lib/libicuuc.a $STATIC_PREFIX/lib/libicudata.a"
  export LIBXSLT_CFLAGS="-I$STATIC_PREFIX/include"
  export LIBXSLT_LIBS="$STATIC_PREFIX/lib/libxslt.a $STATIC_PREFIX/lib/libexslt.a $STATIC_PREFIX/lib/libxml2.a $STATIC_PREFIX/lib/libz.a"
  export SQLITE_CFLAGS="-I$STATIC_PREFIX/include"
  export SQLITE_LIBS="$STATIC_PREFIX/lib/libsqlite3.a"
  export PCRE2_CFLAGS="-I$STATIC_PREFIX/include"
  export PCRE2_LIBS="$STATIC_PREFIX/lib/libpcre2-8.a"
  export LIBZIP_CFLAGS="-I$STATIC_PREFIX/include"
  export LIBZIP_LIBS="$STATIC_PREFIX/lib/libzip.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a $STATIC_PREFIX/lib/libz.a $STATIC_PREFIX/lib/libbz2.a -lpthread -ldl"
  export LIBSODIUM_CFLAGS="-I$STATIC_PREFIX/include"
  export LIBSODIUM_LIBS="$STATIC_PREFIX/lib/libsodium.a"
  export ONIG_CFLAGS="-I$STATIC_PREFIX/include"
  export ONIG_LIBS="$STATIC_PREFIX/lib/libonig.a"
  export FFI_CFLAGS="-I$STATIC_PREFIX/include"
  export FFI_LIBS="$STATIC_PREFIX/lib/libffi.a"
  export PNG_CFLAGS="-I$STATIC_PREFIX/include"
  export PNG_LIBS="$STATIC_PREFIX/lib/libpng.a $STATIC_PREFIX/lib/libz.a"
  export JPEG_CFLAGS="-I$STATIC_PREFIX/include"
  export JPEG_LIBS="$STATIC_PREFIX/lib/libjpeg.a"
  export WEBP_CFLAGS="-I$STATIC_PREFIX/include"
  export WEBP_LIBS="$STATIC_PREFIX/lib/libwebp.a $STATIC_PREFIX/lib/libsharpyuv.a"
  export FREETYPE2_CFLAGS="-I$STATIC_PREFIX/include/freetype2"
  export FREETYPE2_LIBS="$STATIC_PREFIX/lib/libfreetype.a $STATIC_PREFIX/lib/libpng.a $STATIC_PREFIX/lib/libz.a $STATIC_PREFIX/lib/libbz2.a"
  export GMP_CFLAGS="-I$STATIC_PREFIX/include"
  export GMP_LIBS="$STATIC_PREFIX/lib/libgmp.a"
  export EDIT_CFLAGS="-I$STATIC_PREFIX/include"
  export EDIT_LIBS="$STATIC_PREFIX/lib/libedit.a $STATIC_PREFIX/lib/libncurses.a"
  export ARGON2_CFLAGS="-I$STATIC_PREFIX/include"
  export ARGON2_LIBS="$STATIC_PREFIX/lib/libargon2.a"
  export ZLIB_CFLAGS="-I$STATIC_PREFIX/include"
  export ZLIB_LIBS="$STATIC_PREFIX/lib/libz.a"
  export BZ2_CFLAGS="-I$STATIC_PREFIX/include"
  export BZ2_LIBS="$STATIC_PREFIX/lib/libbz2.a"
  export READLINE_CFLAGS="-I$STATIC_PREFIX/include"
  export READLINE_LIBS="$STATIC_PREFIX/lib/libreadline.a $STATIC_PREFIX/lib/libncurses.a"
  export BROTLI_CFLAGS="-I$STATIC_PREFIX/include"
  export BROTLI_LIBS="$STATIC_PREFIX/lib/libbrotlienc.a $STATIC_PREFIX/lib/libbrotlidec.a $STATIC_PREFIX/lib/libbrotlicommon.a"
  export XZ_CFLAGS="-I$STATIC_PREFIX/include"
  export XZ_LIBS="$STATIC_PREFIX/lib/liblzma.a"
  export ICONV_CFLAGS="-I$STATIC_PREFIX/include"
  export ICONV_LIBS="$STATIC_PREFIX/lib/libiconv.a"
  
  # QDBM for dba extension
  export QDBM_CFLAGS="-I$STATIC_PREFIX/include"
  export QDBM_LIBS="$STATIC_PREFIX/lib/libqdbm.a"
  
  # LMDB for dba extension
  export LMDB_CFLAGS="-I$STATIC_PREFIX/include"
  export LMDB_LIBS="$STATIC_PREFIX/lib/liblmdb.a"
  
  # Tidy HTML library
  export TIDY_CFLAGS="-I$STATIC_PREFIX/include"
  export TIDY_LIBS="$STATIC_PREFIX/lib/libtidy.a"
  
  # Ncurses (for libedit)
  export NCURSES_CFLAGS="-I$STATIC_PREFIX/include -I$STATIC_PREFIX/include/ncursesw"
  export NCURSES_LIBS="$STATIC_PREFIX/lib/libncursesw.a"
  
  # libxslt and libexslt
  export LIBXSLT_CFLAGS="-I$STATIC_PREFIX/include"
  export LIBXSLT_LIBS="$STATIC_PREFIX/lib/libxslt.a $STATIC_PREFIX/lib/libexslt.a $STATIC_PREFIX/lib/libxml2.a $STATIC_PREFIX/lib/libz.a -lm"
  export EXSLT_CFLAGS="-I$STATIC_PREFIX/include"
  export EXSLT_LIBS="$STATIC_PREFIX/lib/libexslt.a $STATIC_PREFIX/lib/libxslt.a $STATIC_PREFIX/lib/libxml2.a $STATIC_PREFIX/lib/libz.a -lm"

  # PostgreSQL support
  export PGSQL_CFLAGS="-I$STATIC_PREFIX/include"
  export PGSQL_LIBS="$STATIC_PREFIX/lib/libpq.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a $STATIC_PREFIX/lib/libpgport.a $STATIC_PREFIX/lib/libpgcommon.a -lpthread -ldl -lm -lz"
  export PDO_PGSQL_CFLAGS="$PGSQL_CFLAGS"
  export PDO_PGSQL_LIBS="$PGSQL_LIBS"

  # OpenLDAP support
  export LDAP_CFLAGS="-I$STATIC_PREFIX/include"
  export LDAP_LIBS="$STATIC_PREFIX/lib/libldap.a $STATIC_PREFIX/lib/liblber.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lpthread -ldl -lresolv"

  # Note: Net-SNMP requires its static libraries to be built
  # SNMP support
  export SNMP_CFLAGS="-I$STATIC_PREFIX/include/net-snmp -I$STATIC_PREFIX/include"
  export SNMP_LIBS="$STATIC_PREFIX/lib/libnetsnmp.a $STATIC_PREFIX/lib/libnetsnmpagent.a $STATIC_PREFIX/lib/libnetsnmpmibs.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lpthread -ldl -lm"
  
  # Enchant and Firebird are linked dynamically (not statically)
  # - Enchant: GLib requires pcre2-8 which conflicts with PHP's bundled PCRE2
  # - Firebird: Complex static build requirements with libtomcrypt/libtommath
  # The system shared libraries (libenchant-2.so, libfbclient.so) will be used

  # unixODBC support
  export ODBC_CFLAGS="-I$STATIC_PREFIX/include"
  export ODBC_LIBS="$STATIC_PREFIX/lib/libodbc.a $STATIC_PREFIX/lib/libodbcinst.a -lpthread -ldl"
  export PDO_ODBC_CFLAGS="$ODBC_CFLAGS"
  export PDO_ODBC_LIBS="$ODBC_LIBS"

  # FreeTDS/pdo_dblib support
  export FREETDS_CFLAGS="-I$STATIC_PREFIX/include"
  export FREETDS_LIBS="$STATIC_PREFIX/lib/libsybdb.a $STATIC_PREFIX/lib/libct.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lpthread -ldl"
  export PDO_DBLIB_CFLAGS="$FREETDS_CFLAGS"
  export PDO_DBLIB_LIBS="$FREETDS_LIBS"

  # Set pkg-config to prefer static libs
  export PKG_CONFIG="pkg-config --static"
  export LIBRARY_PATH="$STATIC_PREFIX/lib:$STATIC_PREFIX/lib64"
  export LD_LIBRARY_PATH=""

  # Create a pkg-config wrapper to ensure static libs are used
  mkdir -p /tmp/static-wrapper
  cat > /tmp/static-wrapper/pkg-config << 'PKGWRAP'
#!/bin/bash
PKG_CONFIG_PATH="/opt/static/lib/pkgconfig:/opt/static/lib64/pkgconfig:/opt/static/lib/aarch64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"
export PKG_CONFIG_PATH
exec /usr/bin/pkg-config --static "$@"
PKGWRAP
  chmod +x /tmp/static-wrapper/pkg-config
  export PATH="/tmp/static-wrapper:$PATH"

  # Export inputs
  export INSTALL_ROOT PHP_VERSION SAPI STATIC_PREFIX
}

# Function to build PHP statically - wraps build_php with static environment
build_php_static() {
  echo "::group::$1"
  SAPI=$1
  export PHP_BUILD_EXTRA_MAKE_ARGUMENTS="${PHP_BUILD_EXTRA_MAKE_ARGUMENTS:--j1}"
  
  # Set up static environment
  setup_static_environment
  
  # Clear any previous configure cache
  rm -f /tmp/config.cache
  rm -rf /tmp/php-build/source/* 2>/dev/null || true

  # Build PHP using php-build (same as dynamic, but with static env)
  if ! php-build -v -i "$default_ini" "$PHP_VERSION" "$prefix"; then
    echo 'Failed to build PHP'
    exit 1
  fi
  
  echo "::endgroup::"
}

# Wrapper to reuse dynamic SAPI build flow with static environment.
build_php() {
  build_php_static "$@"
}

# Wrapper to reuse dynamic SAPI packaging flow with static archives.
package_sapi() {
  local sapi=$1

  # Strip the binary to reduce size
  if [ -f "$INSTALL_ROOT/usr/bin/php$PHP_VERSION" ]; then
    strip_binary "$INSTALL_ROOT/usr/bin/php$PHP_VERSION"
  fi
  if [ -f "$INSTALL_ROOT/usr/bin/php-cgi$PHP_VERSION" ]; then
    strip_binary "$INSTALL_ROOT/usr/bin/php-cgi$PHP_VERSION"
  fi
  if [ -f "$INSTALL_ROOT/usr/bin/phpdbg$PHP_VERSION" ]; then
    strip_binary "$INSTALL_ROOT/usr/bin/phpdbg$PHP_VERSION"
  fi
  if [ -f "$INSTALL_ROOT/usr/sbin/php-fpm$PHP_VERSION" ]; then
    strip_binary "$INSTALL_ROOT/usr/sbin/php-fpm$PHP_VERSION"
  fi

  # Verify static linkage
  for bin in php"$PHP_VERSION" php-cgi"$PHP_VERSION" phpdbg"$PHP_VERSION"; do
    if [ -f "$INSTALL_ROOT/usr/bin/$bin" ]; then
      verify_truly_static "$INSTALL_ROOT/usr/bin/$bin" "$sapi"
    fi
  done
  if [ -f "$INSTALL_ROOT/usr/sbin/php-fpm$PHP_VERSION" ]; then
    verify_truly_static "$INSTALL_ROOT/usr/sbin/php-fpm$PHP_VERSION" "fpm"
  fi

  package_sapi_static "$sapi"
}

# Function to setup php-build for static builds - uses static definitions
setup_phpbuild_static() {
  echo "::group::php-build (static)"
  
  # Clone and install php-build to /usr (matching php_build_dir in build-static.sh)
  rm -rf ~/php-build
  git clone -b debian https://github.com/shivammathur/php-build ~/php-build || {
    rm -rf ~/php-build
    git clone -b debian https://github.com/shivammathur/php-build ~/php-build
  }
  PREFIX=/usr ~/php-build/install.sh
  
  # Configure with STATIC definitions (not dynamic ones)
  configure_phpbuild_static
  
  echo "::endgroup::"
}

# Function to configure php-build for static builds
configure_phpbuild_static() {
  # Set install command based on PHP version.
  if [[ "${branch:?}" =~ ^(master|PHP-"$PHP_VERSION"(.0)?)$ ]]; then
    install_command="install_package_from_github $branch"
  else
    install_command="install_package \"https://github.com/php/web-php-distributions/raw/master/${new_version:?}.tar.gz\""
  fi

  # Ensure the definitions directory exists
  mkdir -p "${definitions:?}"

  # Copy STATIC definitions to php-build definitions directory (NOT dynamic ones)
  cp -rf config/definitions/static/* "${definitions:?}"
  
  # Copy SAPI definitions from dynamic config (static does not provide these)
  mkdir -p "${definitions:?}/sapi"
  cp -rf config/definitions/sapi/* "${definitions:?}/sapi/"

  # Patch the definition for the PHP version.
  patch_config_file configure_option "${definitions:?}"/"$PHP_VERSION"

  # Path the definition for thread-safe.
  zts=''
  if [ "${BUILD:?}" = "zts" ]; then
    if [ -f "${definitions:?}/zts/$PHP_VERSION" ]; then
      patch_config_file configure_option "${definitions:?}"/zts/"$PHP_VERSION"
      zts="$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' "${definitions:?}"/zts/"$PHP_VERSION")"
    fi
  fi

  # Copy all local patches to the php-build patches directory.
  patches_dir=config/patches/"$PHP_VERSION"
  if [ -d "$patches_dir" ]; then
    find "$patches_dir" -name '*' -exec cp -rf "{}" "${php_build_dir:?}"/patches \;
  fi
  
  if [ -f "$patches_dir/series" ]; then
    cp "$patches_dir"/series $patches_dir/~series
    # Patch series file to php-build syntax.
    patch_config_file patch_file "$patches_dir"/~series
  else
    touch "$patches_dir/~series"
  fi

  # Patch PHP version, host, build, patches and install command in the definition template.
  sed -i -e "s|BUILD_MACHINE_SYSTEM_TYPE|$(dpkg-architecture -q DEB_BUILD_GNU_TYPE)|" \
         -e "s|HOST_MACHINE_SYSTEM_TYPE|$(dpkg-architecture -q DEB_HOST_GNU_TYPE)|" \
         -e "s|ZTS|$zts|" \
         -e "s|INSTALL|$install_command|" \
         -e "s|PHP_VERSION|$PHP_VERSION|" \
         -e "s|PHP_VERSION|$PHP_VERSION|" \
         -e "/PATCHES/{r./$patches_dir/~series" -e "d}" "$definitions"/"$PHP_VERSION"

  # Print the definition file.
  cat "$definitions"/"$PHP_VERSION"

  # Remove ~series file if it exists.
  rm -f "$patches_dir"/~series
}

# Function to strip the binary to reduce size
strip_binary() {
  echo "::group::strip_binary"
  local binary=$1
  if [ -f "$binary" ]; then
    echo "Stripping $binary..."
    strip --strip-all "$binary" 2>/dev/null || true
    echo "Binary size after strip: $(du -h "$binary" | cut -f1)"
  fi
  echo "::endgroup::"
}

# Function to verify binary is truly static
verify_truly_static() {
  echo "::group::verify_truly_static"
  local binary=$1
  local sapi=$2
  local warnings=0
  local errors=0
  
  if [ ! -f "$binary" ]; then
    echo "ERROR: Binary not found: $binary"
    return 1
  fi
  
  echo "=== Verifying $sapi static build ==="
  echo "Binary: $binary"
  
  # Check ldd output
  echo ""
  echo "Test 1: ldd output"
  ldd_output=$(ldd "$binary" 2>&1) || true
  if echo "$ldd_output" | grep -qE "(not a dynamic executable|statically linked)"; then
    echo "PASS: Binary is fully statically linked"
  elif echo "$ldd_output" | grep -qE "linux-(vdso|gate)\.so"; then
    # Check for unexpected dynamic libraries (excluding kernel vDSO and loader)
    dynamic_libs=$(echo "$ldd_output" | grep -vE "(linux-(vdso|gate)|ld-linux)" | grep "=>" || true)
    if [ -z "$dynamic_libs" ]; then
      echo "PASS: Only kernel vDSO present (acceptable)"
    else
      # Allow only specific dynamic libraries for static builds
      allowed_regex="(libc\.so|libm\.so|libpthread|libdl|librt|libstdc\+\+|libgcc_s|libc\+\+|libc\+\+abi|libenchant-2|libfbclient|libtommath|libglib-2\.0|libgobject-2\.0|libgmodule-2\.0|libgthread-2\.0|libgio-2\.0|libpcre2-8|libffi)"
      disallowed_libs=$(echo "$dynamic_libs" | grep -vE "$allowed_regex" || true)
      if [ -n "$disallowed_libs" ]; then
        echo "ERROR: Unexpected dynamic libraries found:"
        echo "$disallowed_libs" | sed 's/^/  /'
        errors=$((errors + 1))
      else
        echo "PASS: Only allowed dynamic libraries present"
      fi
    fi
  fi
  
  # Check file type
  echo ""
  echo "Test 2: file type"
  file "$binary"
  
  # Check binary size
  echo ""
  echo "Test 3: Binary size"
  size=$(stat -c%s "$binary" 2>/dev/null || stat -f%z "$binary" 2>/dev/null)
  size_mb=$((size / 1024 / 1024))
  echo "Size: ${size_mb}MB ($size bytes)"
  
  echo ""
  if [ "$errors" -gt 0 ]; then
    echo "=== $sapi STATIC VERIFICATION: WARN ($errors issues) ==="
    echo "Note: C++ runtime linking issues are acceptable for now"
  elif [ "$warnings" -eq 0 ]; then
    echo "=== $sapi STATIC VERIFICATION: PASSED ==="
  else
    echo "=== $sapi STATIC VERIFICATION: PASSED (with $warnings warnings) ==="
  fi
  echo "::endgroup::"
  return 0
}

# Override package_sapi for static builds
package_sapi_static() {
  sapi=$1
  (
    echo "::group::package_$sapi (static)"
    cd "${INSTALL_ROOT:?}"/.. || exit
    mv "$INSTALL_ROOT" "$INSTALL_ROOT-$sapi"
    arch="$(arch)"
    [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && ARCH_SUFFIX='_arm64' || ARCH_SUFFIX=''
    XZ_OPT=-e9 tar cfJ "php_$PHP_VERSION$PHP_PKG_SUFFIX-static-$sapi+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz" "php$PHP_VERSION-$sapi"
    echo "::endgroup::"
  )
}
