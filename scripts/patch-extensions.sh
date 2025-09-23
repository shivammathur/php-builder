# Function to patch ast source.
patch_ast() {
  [[ "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i '/ast_register_flag_constant("DIM_ALTERNATIVE_SYNTAX/d' ast.c
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i -e '/ZEND_AST_EXIT/d' -e '/ZEND_AST_CLONE/d'  ast_data.c
}

# Function to configure imagick.
configure_imagick() {
  if pkg-config --exists MagickWand-7.Q16; then
    PKG_WAND=MagickWand-7.Q16
  elif pkg-config --exists MagickWand-6.Q16; then
    PKG_WAND=MagickWand-6.Q16
  else
    echo "MagickWand not found — install libmagickwand-dev" >&2
    exit 1
  fi
  export CPPFLAGS="$(pkg-config --cflags "$PKG_WAND")"
  export LDFLAGS="$(pkg-config --libs "$PKG_WAND")"
}

# Function to patch imagick source.
patch_imagick() {
  configure_imagick
  sed -i 's/spl_ce_Countable/zend_ce_countable/' imagick.c util/checkSymbols.php
  sed -i "s/@PACKAGE_VERSION@/$(grep -Po 'release>\K(\d+\.\d+\.\d+)' package.xml)/" php_imagick.h
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' imagick.c
}

# Function to patch sqlsrv source.
patch_sqlsrv() {
  if [ -d source/sqlsrv ]; then
    cd source/sqlsrv || exit 1
    cp -rf ../shared ./
  fi
}

# Function to patch pdo_sqlsrv source.
patch_pdo_sqlsrv() {
  if [ -d source/pdo_sqlsrv ]; then
    cd source/pdo_sqlsrv || exit 1
    cp -rf ../shared ./
  fi
  if [[ "$PHP_VERSION" = "8.5" ]]; then
    sed -i 's/zval_ptr_dtor( &dbh->query_stmt_zval );/OBJ_RELEASE(dbh->query_stmt_obj);dbh->query_stmt_obj = NULL;/' php_pdo_sqlsrv_int.h
    sed -i 's/pdo_error_mode prev_err_mode/uint8_t prev_err_mode/g' pdo_dbh.cpp
  fi
}

# Function to patch xdebug source.
patch_xdebug() {
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's/80500/80600/g' config.m4
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' src/develop/stack.c src/lib/var.c
  [[ "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" ]] && sed -i -e "s|ext/standard/php_lcg.h|ext/random/php_random.h|" src/lib/usefulstuff.c
}

# Function to patch amqp source.
patch_amqp() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i "s/#include <amqp.h>/#include <errno.h>\n#include <amqp.h>/" php_amqp.h
}

# Function to patch memcache source.
patch_memcache() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i "s/#include <string.h>/#include <string.h>\n#include <errno.h>/" src/memcache_pool.h
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' src/memcache_ascii_protocol.c src/memcache_binary_protocol.c src/memcache_pool.c src/memcache_session.c
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string_public.h#Zend/zend_smart_string.h#' src/memcache_pool.h
}

# Function to patch memcached source.
patch_memcached() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" ]] && sed -i "s/#include \"php.h\"/#include <errno.h>\n#include \"php.h\"/" php_memcached.h
}

# Function to patch redis source.
patch_redis() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i "s/#include <sys\/types.h>/#include <errno.h>\n#include <sys\/types.h>/" library.c
  if [[ "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]]; then
    sed -i -e "s|ext/standard/php_rand.h|ext/random/php_random.h|" library.c
    sed -i -e "s|ext/standard/php_rand.h|ext/random/php_random.h|" -e "/php_mt_rand.h/d" backoff.c
    sed -i -e "s|standard/php_random.h|ext/random/php_random.h|" redis.c
  fi
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#zend_smart_string.h#' common.h
}

# Function to patch igbinary source.
patch_igbinary() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && find . -type f -exec sed -i 's/zend_uintptr_t/uintptr_t/g' {} +;
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' src/php7/php_igbinary.h
}

# Function to path yaml source
patch_yaml() {
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' php_yaml.h
}

# Function to path zmq source
patch_zmq() {
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's/zend_exception_get_default()/zend_ce_exception/' zmq.c
}

patch_mongodb() {
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's/IS_INTERNED/ZSTR_IS_INTERNED/' src/contrib/php_array_api.h
}
