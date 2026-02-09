#!/usr/bin/env bash

extension=$1
repo=$2
tag=$3
INSTALL_ROOT=$4
shift 4
params=("$@")

. scripts/patch-extensions.sh

# Function to setup static linking environment for PECL extensions
setup_static_extension_env() {
  local ext_name=$1
  STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
  
  # Only apply static linking if static prefix exists and has libraries
  if [ ! -d "$STATIC_PREFIX/lib" ]; then
    return 0
  fi
  
  # Set common static build flags
  export CFLAGS="-O2 -fPIC -I$STATIC_PREFIX/include ${CFLAGS:-}"
  export CPPFLAGS="-I$STATIC_PREFIX/include ${CPPFLAGS:-}"
  export LDFLAGS="-L$STATIC_PREFIX/lib -L$STATIC_PREFIX/lib64 ${LDFLAGS:-}"
  export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
  
  # Use static pkg-config wrapper if available
  if [ -x "$STATIC_PREFIX/bin/pkg-config-static" ]; then
    export PKG_CONFIG="$STATIC_PREFIX/bin/pkg-config-static"
  fi
  
  # Extension-specific static library linking
  case "$ext_name" in
    yaml)
      if [ -f "$STATIC_PREFIX/lib/libyaml.a" ]; then
        export YAML_CFLAGS="-I$STATIC_PREFIX/include"
        export YAML_LIBS="$STATIC_PREFIX/lib/libyaml.a"
        export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libyaml.a"
      fi
      ;;
    zmq)
      if [ -f "$STATIC_PREFIX/lib/libzmq.a" ]; then
        export ZMQ_CFLAGS="-I$STATIC_PREFIX/include"
        export ZMQ_LIBS="$STATIC_PREFIX/lib/libzmq.a -lstdc++ -lpthread"
        export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libzmq.a -lstdc++ -lpthread"
        # ZMQ needs sodium
        if [ -f "$STATIC_PREFIX/lib/libsodium.a" ]; then
          export ZMQ_LIBS="$ZMQ_LIBS $STATIC_PREFIX/lib/libsodium.a"
          export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libsodium.a"
        fi
      fi
      ;;
    memcache)
      if [ -f "$STATIC_PREFIX/lib/libz.a" ]; then
        export ZLIB_CFLAGS="-I$STATIC_PREFIX/include"
        export ZLIB_LIBS="$STATIC_PREFIX/lib/libz.a"
        export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libz.a"
      fi
      ;;
    mongodb)
      # MongoDB needs OpenSSL, zlib, zstd
      MONGO_LIBS=""
      if [ -f "$STATIC_PREFIX/lib/libssl.a" ]; then
        export OPENSSL_CFLAGS="-I$STATIC_PREFIX/include"
        export OPENSSL_LIBS="$STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lpthread -ldl"
        MONGO_LIBS="$MONGO_LIBS $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a"
      fi
      if [ -f "$STATIC_PREFIX/lib/libz.a" ]; then
        MONGO_LIBS="$MONGO_LIBS $STATIC_PREFIX/lib/libz.a"
      fi
      export LDFLAGS="$LDFLAGS $MONGO_LIBS -lpthread -ldl -lresolv"
      ;;
    xdebug)
      if [ -f "$STATIC_PREFIX/lib/libz.a" ]; then
        export ZLIB_CFLAGS="-I$STATIC_PREFIX/include"
        export ZLIB_LIBS="$STATIC_PREFIX/lib/libz.a"
        export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libz.a"
      fi
      ;;
    memcached)
      # memcached extension needs libmemcached
      if [ -f "$STATIC_PREFIX/lib/libmemcached.a" ]; then
        export LIBMEMCACHED_CFLAGS="-I$STATIC_PREFIX/include"
        export LIBMEMCACHED_LIBS="$STATIC_PREFIX/lib/libmemcached.a $STATIC_PREFIX/lib/libmemcachedutil.a -lpthread"
        export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libmemcached.a $STATIC_PREFIX/lib/libmemcachedutil.a -lpthread"
        if [ -f "$STATIC_PREFIX/lib/libz.a" ]; then
          export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libz.a"
        fi
      fi
      ;;
    imap)
      # imap needs c-client and ssl; use static libs when available
      IMAP_LIBS=""
      if [ -f "$STATIC_PREFIX/lib/libc-client.a" ]; then
        export IMAP_CFLAGS="-I$STATIC_PREFIX/include"
        IMAP_LIBS="$IMAP_LIBS $STATIC_PREFIX/lib/libc-client.a"
      fi
      if [ -f "$STATIC_PREFIX/lib/libssl.a" ]; then
        IMAP_LIBS="$IMAP_LIBS $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a"
      fi
      if [ -f "$STATIC_PREFIX/lib/libz.a" ]; then
        IMAP_LIBS="$IMAP_LIBS $STATIC_PREFIX/lib/libz.a"
      fi
      if [ -f "$STATIC_PREFIX/lib/libkrb5.a" ]; then
        IMAP_LIBS="$IMAP_LIBS $STATIC_PREFIX/lib/libkrb5.a $STATIC_PREFIX/lib/libgssapi_krb5.a $STATIC_PREFIX/lib/libk5crypto.a $STATIC_PREFIX/lib/libcom_err.a"
      fi
      if [ -n "$IMAP_LIBS" ]; then
        export IMAP_LIBS
        export LIBS="$IMAP_LIBS -lcrypt -ldl -lpthread ${LIBS:-}"
      fi
      ;;
    imagick)
      # Use static ImageMagick via pkg-config when available
      MAGICKWAND_PC=""
      if pkg-config --exists MagickWand-7.Q16HDRI 2>/dev/null; then
        MAGICKWAND_PC="MagickWand-7.Q16HDRI"
      elif pkg-config --exists MagickWand-7.Q16 2>/dev/null; then
        MAGICKWAND_PC="MagickWand-7.Q16"
      elif pkg-config --exists MagickWand 2>/dev/null; then
        MAGICKWAND_PC="MagickWand"
      fi
      if [ -n "$MAGICKWAND_PC" ]; then
        export MAGICKWAND_CFLAGS="$(pkg-config --cflags "$MAGICKWAND_PC")"
        export MAGICKWAND_LIBS="$(pkg-config --libs "$MAGICKWAND_PC")"
        export LDFLAGS="$LDFLAGS $MAGICKWAND_LIBS"
      fi
      ;;
    sqlsrv|pdo_sqlsrv)
      # ODBC extensions need libodbc - link statically if available
      if [ -f "$STATIC_PREFIX/lib/libodbc.a" ]; then
        export ODBC_CFLAGS="-I$STATIC_PREFIX/include"
        export ODBC_LIBS="$STATIC_PREFIX/lib/libodbc.a $STATIC_PREFIX/lib/libodbcinst.a"
        export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libodbc.a $STATIC_PREFIX/lib/libodbcinst.a -lpthread -ldl"
      fi
      if [ -f "$STATIC_PREFIX/lib/libiconv.a" ]; then
        export ICONV_CFLAGS="-I$STATIC_PREFIX/include"
        export ICONV_LIBS="$STATIC_PREFIX/lib/libiconv.a"
        export LDFLAGS="$LDFLAGS $STATIC_PREFIX/lib/libiconv.a"
        export LIBS="$LIBS $STATIC_PREFIX/lib/libiconv.a"
      fi
      ;;
  esac
}

get_latest_git_tag() {
  local repo_url="$1"
  local repo_slug repo_owner repo_name latest_tag graph_query

  repo_slug="$(echo "$repo_url" | sed -E 's|^https?://github.com/||; s|^git@github.com:||; s|\.git$||; s|/$||')"
  if [[ -z "$repo_slug" || "$repo_slug" = "$repo_url" || "$repo_slug" != */* ]]; then
    echo "Unsupported repository URL: $repo_url" >&2
    exit 1
  fi

  repo_owner="${repo_slug%%/*}"
  repo_name="${repo_slug##*/}"

  # Try gh CLI first if available
  if command -v gh >/dev/null 2>&1; then
    graph_query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){refs(refPrefix:"refs/tags/",first:1,orderBy:{field:TAG_COMMIT_DATE,direction:DESC}){nodes{name}}}}'
    latest_tag=$(gh api graphql -f owner="$repo_owner" -f name="$repo_name" -f query="$graph_query" --jq '.data.repository.refs.nodes[0].name' 2>/dev/null || true)
    if [ -z "$latest_tag" ]; then
      latest_tag=$(gh release list --repo "$repo_slug" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)
    fi
  fi

  # Fallback to GitHub API via curl if gh failed or unavailable
  if [ -z "$latest_tag" ]; then
    latest_tag=$(curl -sL "https://api.github.com/repos/$repo_slug/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' || true)
  fi

  # Fallback to git ls-remote
  if [ -z "$latest_tag" ]; then
    latest_tag=$(git ls-remote --tags --sort=-v:refname "$repo_url" 2>/dev/null | head -1 | sed -E 's|.*refs/tags/||; s|\^{}||' || true)
  fi

  if [ -z "$latest_tag" ]; then
    echo "Could not determine latest tag for $repo_url" >&2
    exit 1
  fi

  printf '%s' "$latest_tag"
}

if [[ "$repo" != "pecl" && "$tag" = "latest" ]]; then
  tag="$(get_latest_git_tag "$repo")"
fi

# Fetch the extension source.
if [ "$repo" = "pecl" ]; then
  pecl_bin="$INSTALL_ROOT/usr/bin/pecl"
  if [ ! -x "$pecl_bin" ]; then
    pecl_bin="/usr/bin/pecl"
  fi
  if [ -n "${tag// }" ]; then
    "$pecl_bin" download "$extension-$tag"
  else
    "$pecl_bin" download "$extension"
  fi
  mv "$extension"*.tgz /tmp/"$extension".tar.gz
else
  curl -o "/tmp/$extension.tar.gz" -sSL "$repo/archive/${tag/\//%2f}.tar.gz"
fi

# Extract it to /tmp and build the extension in INSTALL_ROOT
if [ "$repo" = "pecl" ]; then
  rm -rf /tmp/"$extension"-*
else
  repo_base="$(basename "$repo")"
  rm -rf /tmp/"$repo_base"-*
fi
tar xf "/tmp/$extension.tar.gz" -C /tmp
(
  if [ "$repo" = "pecl" ]; then
    cd /tmp/"$extension"-* || exit 1
  else
    tag=${tag#v}
    cd /tmp/"$(basename "$repo")"-"${tag/\//-}" || exit 1
  fi
  export SED=$(command -v sed)
  patch_"${extension}" 2>/dev/null || true
  
  # Setup static linking environment if available
  setup_static_extension_env "$extension"
  
  phpize
  ./configure "--with-php-config=/usr/bin/php-config" "${params[@]}"
  make -j"$(nproc)"
  make install
  # shellcheck disable=SC2097
  # shellcheck disable=SC2098
  INSTALL_ROOT="$INSTALL_ROOT" make install DESTDIR="$INSTALL_ROOT"
)
