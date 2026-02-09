# Extension-specific static build configurations
# Each file defines how to build a specific extension with static library dependencies
#
# Variables:
#   EXT_DEPS          - Space-separated list of required static libraries
#   EXT_STATIC_LIBS   - Static library flags to link
#   EXT_STATIC_CFLAGS - Compiler flags needed
#   EXT_PKG_CONFIG    - pkg-config packages to query
#   EXT_CONFIGURE_ARGS - Additional configure arguments
#   EXT_PRE_BUILD     - Commands to run before phpize
#   EXT_POST_BUILD    - Commands to run after make

STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"

# yaml extension config
yaml() {
  EXT_PKG_CONFIG="yaml-0.1"
  EXT_DEPS="libyaml"
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libyaml.a"
  EXT_CONFIGURE_ARGS="--with-yaml=$STATIC_PREFIX"
}

# memcached extension config
memcached() {
  EXT_PKG_CONFIG="libmemcached"
  EXT_DEPS="libmemcached zlib"
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libmemcached.a $STATIC_PREFIX/lib/libmemcachedutil.a $STATIC_PREFIX/lib/libhashkit.a -lpthread"
  EXT_CONFIGURE_ARGS="--with-libmemcached-dir=$STATIC_PREFIX --disable-memcached-sasl --with-zlib-dir=$STATIC_PREFIX"
}

# memcache extension config (simpler than memcached)
memcache() {
  EXT_DEPS="zlib"
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libz.a"
  EXT_CONFIGURE_ARGS="--enable-memcache --with-zlib-dir=$STATIC_PREFIX"
}

# zmq extension config  
# NOTE: zmq extension 1.1.3 is incompatible with PHP 8.4+ (uses deprecated TSRMLS macros)
# A fork or updated version is needed for PHP 8.4+
zmq() {
  EXT_PKG_CONFIG="libzmq"
  EXT_DEPS="zeromq libsodium"
  local gcc_lib_dir
  gcc_lib_dir=$(dirname "$(g++ --print-file-name=libstdc++.a)" 2>/dev/null || echo "/usr/lib/gcc/aarch64-linux-gnu/13")
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libzmq.a $STATIC_PREFIX/lib/libsodium.a -lpthread $gcc_lib_dir/libstdc++.a -lrt"
  EXT_CONFIGURE_ARGS="--with-zmq=$STATIC_PREFIX"
}

# imagick extension config
imagick() {
  EXT_PKG_CONFIG="MagickWand-7.Q16HDRI MagickWand-7.Q16 MagickWand-6.Q16HDRI MagickWand-6.Q16 MagickWand"
  EXT_DEPS="imagemagick libjpeg libpng freetype libwebp zlib bzip2"
  local gcc_lib_dir
  gcc_lib_dir=$(dirname "$(g++ --print-file-name=libstdc++.a)" 2>/dev/null || echo "/usr/lib/gcc/aarch64-linux-gnu/13")
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include/ImageMagick-7 -I$STATIC_PREFIX/include/ImageMagick-6"
  # ImageMagick has complex deps - try to use pkg-config
  if pkg-config --exists MagickWand 2>/dev/null; then
    EXT_STATIC_LIBS="$(pkg-config --static --libs MagickWand 2>/dev/null || echo "-lMagickWand-7.Q16HDRI -lMagickCore-7.Q16HDRI") $gcc_lib_dir/libstdc++.a"
  else
    EXT_STATIC_LIBS="-lMagickWand-7.Q16HDRI -lMagickCore-7.Q16HDRI -lpng16 -ljpeg -lwebp -lfreetype -lz -lbz2 -lm -lpthread $gcc_lib_dir/libstdc++.a"
  fi
  EXT_CONFIGURE_ARGS="--with-imagick=$STATIC_PREFIX"
}

# mongodb extension config
mongodb() {
  EXT_DEPS="openssl zlib"
  local gcc_lib_dir
  gcc_lib_dir=$(dirname "$(g++ --print-file-name=libstdc++.a)" 2>/dev/null || echo "/usr/lib/gcc/aarch64-linux-gnu/13")
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  # MongoDB bundles its own bson/mongoc
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a $STATIC_PREFIX/lib/libz.a -lpthread -lrt -lm $gcc_lib_dir/libstdc++.a"
}

# imap extension config
imap() {
  EXT_PKG_CONFIG="imap"
  EXT_DEPS="imap openssl"
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libc-client.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lcrypt"
  EXT_CONFIGURE_ARGS="--with-imap=$STATIC_PREFIX --with-imap-ssl=$STATIC_PREFIX --with-kerberos"
}

# sqlsrv extensions config
sqlsrv() {
  EXT_PKG_CONFIG="odbc"
  EXT_DEPS="unixodbc"
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libodbc.a $STATIC_PREFIX/lib/libodbcinst.a -lpthread -ldl"
}

pdo_sqlsrv() {
  EXT_PKG_CONFIG="odbc"
  EXT_DEPS="unixodbc"
  EXT_STATIC_CFLAGS="-I$STATIC_PREFIX/include"
  EXT_STATIC_LIBS="$STATIC_PREFIX/lib/libodbc.a $STATIC_PREFIX/lib/libodbcinst.a -lpthread -ldl"
}

# redis extension config (optional igbinary, lzf)
redis() {
  EXT_DEPS=""
  EXT_STATIC_CFLAGS=""
  EXT_STATIC_LIBS=""
  # Redis extension is mostly pure PHP, optional deps are handled by PHP build
  EXT_CONFIGURE_ARGS="--enable-redis-igbinary --enable-redis-msgpack --enable-redis-lzf"
}

# xdebug extension config
xdebug() {
  EXT_DEPS=""
  EXT_STATIC_CFLAGS=""
  EXT_STATIC_LIBS=""
  # xdebug is pure PHP, no external deps
}

# Extensions with no external dependencies
apcu() { EXT_DEPS=""; EXT_STATIC_CFLAGS=""; EXT_STATIC_LIBS=""; }
ast() { EXT_DEPS=""; EXT_STATIC_CFLAGS=""; EXT_STATIC_LIBS=""; }
ds() { EXT_DEPS=""; EXT_STATIC_CFLAGS=""; EXT_STATIC_LIBS=""; }
igbinary() { EXT_DEPS=""; EXT_STATIC_CFLAGS=""; EXT_STATIC_LIBS=""; }
msgpack() { EXT_DEPS=""; EXT_STATIC_CFLAGS=""; EXT_STATIC_LIBS=""; }
pcov() { EXT_DEPS=""; EXT_STATIC_CFLAGS=""; EXT_STATIC_LIBS=""; }
