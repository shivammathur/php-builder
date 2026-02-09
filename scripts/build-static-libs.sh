#!/bin/bash
# Build additional static libraries for PHP extensions

set -e

STATIC_PREFIX=/opt/static
export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
export CFLAGS="-I$STATIC_PREFIX/include -fPIC -O2"
export CPPFLAGS="-I$STATIC_PREFIX/include"
export CXXFLAGS="-I$STATIC_PREFIX/include -fPIC -O2"
export LDFLAGS="-L$STATIC_PREFIX/lib"

# Build ImageMagick static library
build_imagemagick() {
  echo "=== Building ImageMagick ==="
  cd /tmp
  rm -rf ImageMagick* imagemagick*
  
  curl -sL https://github.com/ImageMagick/ImageMagick/archive/refs/tags/7.1.1-43.tar.gz -o imagemagick.tar.gz
  tar xzf imagemagick.tar.gz
  cd ImageMagick-7.1.1-43
  
  ./configure \
    --prefix=$STATIC_PREFIX \
    --enable-static \
    --disable-shared \
    --disable-docs \
    --disable-deprecated \
    --without-perl \
    --without-magick-plus-plus \
    --without-x \
    --without-openexr \
    --without-heic \
    --without-jxl \
    --without-raw \
    --without-djvu \
    --without-rsvg \
    --without-wmf \
    --without-lqr \
    --without-fftw \
    --without-fontconfig \
    --without-openjp2 \
    --without-pango \
    --with-zlib=$STATIC_PREFIX \
    --with-bzlib=$STATIC_PREFIX
  
  make -j$(nproc)
  make install
  
  echo "ImageMagick installed: $(ls -la $STATIC_PREFIX/lib/libMagick*.a 2>/dev/null | wc -l) static libs"
}

# Build c-client (istrstrmap) static library
build_cclient() {
  echo "=== Building c-client (UW-IMAP) ==="
  cd /tmp
  rm -rf imap* uw-imap*
  
  # Get UW-IMAP source
  curl -sL https://github.com/ strstr/uw-imap/archive/refs/heads/master.tar.gz -o uw-imap.tar.gz
  tar xzf uw-imap.tar.gz
  cd uw-imap-master
  
  # Apply touch for fs dependencies
  touch ip6
  
  # Build with SSL support
  make lnp EXTRACFLAGS="-fPIC -I$STATIC_PREFIX/include" \
           EXTRALDFLAGS="-L$STATIC_PREFIX/lib" \
           SSLDIR=$STATIC_PREFIX \
           SSLTYPE=unix
  
  # Install
  cp c-client/c-client.a $STATIC_PREFIX/lib/libc-client.a
  mkdir -p $STATIC_PREFIX/include/c-client
  cp c-client/*.h $STATIC_PREFIX/include/c-client/
  
  echo "c-client installed: $(ls -la $STATIC_PREFIX/lib/libc-client.a)"
}

# Build cyrus-sasl static (for mongodb)
build_sasl() {
  echo "=== Building cyrus-sasl ==="
  cd /tmp
  rm -rf cyrus-sasl*
  
  curl -sL https://github.com/cyrusimap/cyrus-sasl/releases/download/cyrus-sasl-2.1.28/cyrus-sasl-2.1.28.tar.gz -o cyrus-sasl.tar.gz
  tar xzf cyrus-sasl.tar.gz
  cd cyrus-sasl-2.1.28
  
  ./configure \
    --prefix=$STATIC_PREFIX \
    --enable-static \
    --disable-shared \
    --with-openssl=$STATIC_PREFIX \
    --without-saslauthd \
    --without-authdaemond \
    --disable-sample \
    --disable-cram \
    --disable-digest \
    --disable-otp \
    --disable-plain \
    --enable-login \
    --disable-anon \
    --disable-gssapi
  
  make -j$(nproc)
  make install
  
  echo "cyrus-sasl installed: $(ls -la $STATIC_PREFIX/lib/libsasl*.a)"
}

case "$1" in
  imagemagick)
    build_imagemagick
    ;;
  cclient)
    build_cclient
    ;;
  sasl)
    build_sasl
    ;;
  all)
    build_imagemagick
    build_cclient
    build_sasl
    ;;
  *)
    echo "Usage: $0 {imagemagick|cclient|sasl|all}"
    exit 1
    ;;
esac

echo "=== Done ==="
