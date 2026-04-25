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
  [[ "$PHP_VERSION" = "5.6" ]] && export CFLAGS="$CFLAGS -Wno-incompatible-pointer-types -Wno-int-conversion"
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
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/INI_BOOL( warnings_as_errors )/zend_ini_bool_literal(INI_PREFIX INI_WARNINGS_RETURN_AS_ERRORS)/' init.cpp
    sed -i 's/INI_INT( severity )/zend_ini_long_literal(INI_PREFIX INI_LOG_SEVERITY)/' init.cpp
    sed -i 's/INI_INT( subsystems )/zend_ini_long_literal(INI_PREFIX INI_LOG_SUBSYSTEMS)/' init.cpp
    sed -i 's/INI_INT( buffered_limit )/zend_ini_long_literal(INI_PREFIX INI_BUFFERED_QUERY_LIMIT)/' init.cpp
    sed -i 's/INI_INT(set_locale_info)/zend_ini_long_literal(INI_PREFIX INI_SET_LOCALE_INFO)/' init.cpp
  fi
}

# Function to patch pdo_sqlsrv source.
patch_pdo_sqlsrv() {
  if [ -d source/pdo_sqlsrv ]; then
    cd source/pdo_sqlsrv || exit 1
    cp -rf ../shared ./
  fi
  if [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/zval_ptr_dtor( &dbh->query_stmt_zval );/OBJ_RELEASE(dbh->query_stmt_obj);dbh->query_stmt_obj = NULL;/' php_pdo_sqlsrv_int.h
    sed -i 's/pdo_error_mode prev_err_mode/uint8_t prev_err_mode/g' pdo_dbh.cpp
  fi
}

# Function to patch xdebug source.
patch_xdebug() {
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's/80600/80700/g' config.m4
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' src/develop/stack.c src/lib/var.c
  [[ "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" ]] && sed -i -e "s|ext/standard/php_lcg.h|ext/random/php_random.h|" src/lib/usefulstuff.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/ZSTR_INIT_LITERAL(tmp_name, false)/zend_string_init(tmp_name, strlen(tmp_name), false)/g' src/profiler/profiler.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/WRONG_PARAM_COUNT;/zend_wrong_param_count();RETURN_THROWS();/' src/develop/php_functions.c
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    for file in src/debugger/debugger.c src/debugger/handler_dbgp.c src/base/base.c; do
      sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' $file
    done
    sed -i 's/INI_STR((char\*) /zend_ini_string_literal(/g' src/develop/stack.c
  fi
}

# Function to patch amqp source.
patch_amqp() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i "s/#include <amqp.h>/#include <errno.h>\n#include <amqp.h>/" php_amqp.h
}

# Function to patch imap source.
patch_imap() {
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/INI_STR(/zend_ini_string_literal(/g' php_imap.c
}

# Function to patch memcache source.
patch_memcache() {
  [[ "$PHP_VERSION" = "5.6" ]] && export CFLAGS="$CFLAGS -Wno-incompatible-pointer-types"
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i "s/#include <string.h>/#include <string.h>\n#include <errno.h>/" src/memcache_pool.h
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' src/memcache_ascii_protocol.c src/memcache_binary_protocol.c src/memcache_pool.c src/memcache_session.c
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string_public.h#Zend/zend_smart_string.h#' src/memcache_pool.h
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/WRONG_PARAM_COUNT;/zend_wrong_param_count();RETURN_THROWS();/' src/memcache.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i '/^ZEND_EXTERN_MODULE_GLOBALS(memcache)$/a #define ps_create_sid_memcache php_session_create_id\n#define ps_validate_sid_memcache php_session_validate_sid' src/memcache_session.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/path = save_path;/path = ZSTR_VAL(save_path);/' src/memcache_session.c
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    for file in src/memcache_pool.c src/memcache_session.c src/memcache_binary_protocol.c src/memcache.c; do
      sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' $file
    done
    sed -i 's/INI_INT(/zend_ini_long_literal(/g' src/memcache_session.c
  fi
}

# Function to patch pcov source.
patch_pcov() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/INI_BOOL(/zend_ini_bool_literal(/g' pcov.c
    sed -i 's/INI_INT(/zend_ini_long_literal(/g' pcov.c
    sed -i 's/INI_STR(/zend_ini_string_literal(/g' pcov.c
  fi
}

# Function to patch memcached source.
patch_memcached() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" ]] && sed -i "s/#include \"php.h\"/#include <errno.h>\n#include \"php.h\"/" php_memcached.h
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' php_memcached.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i \
    -e 's|if (strstr(save_path, "PERSISTENT="))|if (strstr(ZSTR_VAL(save_path), "PERSISTENT="))|' \
    -e 's|servers = memcached_servers_parse(save_path);|servers = memcached_servers_parse(ZSTR_VAL(save_path));|' \
    -e 's|"memc-session:%s", save_path);|"memc-session:%s", ZSTR_VAL(save_path));|' \
    php_memcached_session.c
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
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/WRONG_PARAM_COUNT;/zend_wrong_param_count();RETURN_THROWS();/' redis_cluster.c
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    for file in library.c redis_commands.c cluster_library.c; do
      sed -i 's/zval_is_true/zend_is_true/' $file
    done
    for file in redis_array_impl.c redis_array.c redis_commands.c redis_cluster.c cluster_library.c library.c redis.c redis_session.c; do
      sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' $file
    done
    for file in redis.c redis_cluster.c; do
      sed -i 's/ZEND_WRONG_PARAM_COUNT();/zend_wrong_param_count();RETURN_THROWS();/' $file
    done
    for file in redis_session.c library.c redis_array_impl.c cluster_library.h redis_cluster.c; do
      sed -i 's/INI_INT(/zend_ini_long_literal(/g' $file
      sed -i 's/INI_STR(/zend_ini_string_literal(/g' $file
    done
    sed -i 's/strlen(save_path)/ZSTR_LEN(save_path)/g' redis_session.c
    sed -i 's/save_path\[/ZSTR_VAL(save_path)[/g' redis_session.c
    sed -i 's/save_path+i/ZSTR_VAL(save_path)+i/g' redis_session.c
    sed -i 's/estrdup(save_path)/estrdup(ZSTR_VAL(save_path))/g' redis_session.c
    sed -i 's/EMPTY_SWITCH_DEFAULT_CASE()/default: ZEND_UNREACHABLE();/' library.c
  fi
}

# Function to patch ast source.
patch_ast() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    for file in ast.c ast_data.c; do
      sed -i 's/ZEND_AST_METHOD_REFERENCE/ZEND_AST_TRAIT_METHOD_REFERENCE/g' "$file"
    done
    sed -i 's/zend_parse_parameters_throw/zend_parse_parameters/g' ast.c
    sed -i 's/ZEND_PARSE_PARAMS_THROW/0/g' ast.c
    sed -i 's/EMPTY_SWITCH_DEFAULT_CASE()/default: ZEND_UNREACHABLE();/' ast.c
  fi
}

# Function to patch igbinary source.
patch_igbinary() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && find . -type f -exec sed -i 's/zend_uintptr_t/uintptr_t/g' {} +;
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' src/php7/php_igbinary.h
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' src/php7/igbinary.c
}

# Function to path yaml source
patch_yaml() {
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' php_yaml.h
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    for file in yaml.c parse.c; do
      sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' $file
    done
  fi
}

# Function to path zmq source
patch_zmq() {
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's/zend_exception_get_default()/zend_ce_exception/' zmq.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/zval_is_true/zend_is_true/' zmq_device.c
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    for file in zmq_pollset.c php5/zmq_pollset.c php5/zmq.c zmq.c; do
      sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' $file
    done
  fi
}

# Function to patch mongodb source.
patch_mongodb() {
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/ZVAL_IS_NULL/Z_ISNULL_P/' src/MongoDB/ServerApi.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/zval_is_true/zend_is_true/' src/MongoDB/ServerApi.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' src/MongoDB/Cursor.c
}

# Function to patch apcu source.
patch_apcu() {
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' apc_cache.c
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/EMPTY_SWITCH_DEFAULT_CASE()/default: ZEND_UNREACHABLE();/g' apc_persist.c
}

# Function to patch msgpack source.
patch_msgpack() {
 if [[ "$PHP_VERSION" = "8.6" ]]; then
   for file in msgpack.c msgpack_unpack.c; do
     sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' $file
   done
 fi
}
