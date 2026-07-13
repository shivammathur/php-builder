# shellcheck shell=bash
# shellcheck disable=SC2016
# Function to add CFLAGS without duplicating them across extension patches.
add_cflags() {
  local flag
  for flag in "$@"; do
    case " $CFLAGS " in
      *" $flag "*) ;;
      *) CFLAGS="${CFLAGS:+$CFLAGS }$flag" ;;
    esac
  done
  export CFLAGS
}

# Function to patch sources using the removed Zend XtOffsetOf macro.
patch_xt_offsetof_file() {
  local file=$1
  [ -f "$file" ] || return 0
  sed -i 's/XtOffsetOf/offsetof/g' "$file"
}

# Function to patch all XtOffsetOf usages under a source tree.
patch_xt_offsetof_tree() {
  local root=${1:-.}
  local file
  while IFS= read -r file; do
    patch_xt_offsetof_file "$file"
  done < <(grep -rl --exclude-dir=.git 'XtOffsetOf' "$root" 2>/dev/null || true)
}

# Function to configure compiler flags for legacy extensions.
configure_legacy_extension_flags() {
  [[ "$PHP_VERSION" = "5.6" ]] && add_cflags -Wno-incompatible-pointer-types -Wno-int-conversion -Wno-implicit-function-declaration
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
  [[ "$PHP_VERSION" = "5.6" ]] && add_cflags -Wno-incompatible-pointer-types -Wno-int-conversion
  CPPFLAGS="$(pkg-config --cflags "$PKG_WAND")"
  LDFLAGS="$(pkg-config --libs "$PKG_WAND")"
  export CPPFLAGS
  export LDFLAGS
}

# Function to patch imagick source.
patch_imagick() {
  local package_xml
  configure_imagick
  package_xml=package.xml
  [ -f "$package_xml" ] || package_xml=../package.xml
  sed -i "s/@PACKAGE_VERSION@/$(grep -Po 'release>\K(\d+\.\d+\.\d+)' "$package_xml")/" php_imagick.h
  [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i 's#ext/standard/php_smart_string.h#Zend/zend_smart_string.h#' imagick.c
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    patch_xt_offsetof_tree .
  fi
}

# Function to patch SQL Server stream wrapper error reporting.
patch_sqlsrv_stream_error() {
  if [[ "$PHP_VERSION" = "8.6" && -f shared/core_stream.cpp ]]; then
    sed -i 's/php_stream_context\* STREAMS_DC/php_stream_context* context STREAMS_DC/' shared/core_stream.cpp
    sed -i 's/php_stream_wrapper_log_error(wrapper, options, "Invalid option: no options except REPORT_ERRORS may be specified with a sqlsrv stream");/php_stream_wrapper_warn(wrapper, context, options, InvalidParam, "Invalid option: no options except REPORT_ERRORS may be specified with a sqlsrv stream");/' shared/core_stream.cpp
  fi
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
    patch_sqlsrv_stream_error
  fi
}

# Function to patch swoole source.
patch_swoole() {
  if [[ "$PHP_VERSION" = "7.2" || "$PHP_VERSION" = "7.3" ]]; then
    sed -i 's/PHP_ADD_LIBRARY(atomic/: #/' config.m4
  fi
  if [ -f include/swoole_proxy.h ]; then
    sed -i 's/#include <string>/#include <string>\n#include <cstdint>/' include/swoole_proxy.h
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
  patch_sqlsrv_stream_error
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

# Function to move to xhprof extension source.
patch_xhprof() {
  if [ -d extension ]; then
    cd extension || return 1
  fi
}

# Function to patch SPL class symbols renamed in PHP 8.6.
patch_spl_symbols() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    for symbol in Aggregate ArrayAccess Countable Iterator Serializable Stringable Traversable; do
      lower_symbol="$(printf '%s' "$symbol" | tr '[:upper:]' '[:lower:]')"
      find . -type f -exec sed -i "s/spl_ce_$symbol/zend_ce_$lower_symbol/g" {} +
    done
  fi
}

# Function to patch amqp source.
patch_amqp() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]] && sed -i "s/#include <amqp.h>/#include <errno.h>\n#include <amqp.h>/" php_amqp.h
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    patch_xt_offsetof_tree .
    for file in amqp_channel.c amqp_connection.c amqp_queue.c; do
      sed -i "s/INI_FLT(/zend_ini_double_literal(/g" "$file"
      sed -i "s/INI_INT(/zend_ini_long_literal(/g" "$file"
      sed -i "s/INI_STR(/zend_ini_string_literal(/g" "$file"
    done
  fi
}

# Function to patch excimer source.
patch_excimer() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/INI_INT(/zend_ini_long_literal(/g' excimer.c
    patch_xt_offsetof_tree .
  fi
}

# Function to patch decimal source.
patch_decimal() {
  if [[ "$PHP_VERSION" =~ 7.[0-3] ]]; then
    sed -i 's/static zval \*php_decimal_write_property(zval/static void php_decimal_write_property(zval/' php_decimal.c
    sed -i '/static void php_decimal_write_property(zval/,/^}/ s/return &EG(uninitialized_zval);/return;/' php_decimal.c
  fi
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/INI_INT("opcache.optimization_level")/zend_ini_long_literal("opcache.optimization_level")/g' php_decimal.c
    sed -i 's/ZEND_PARSE_PARAMS_THROW/0/g' src/params.h
  fi
}

# Function to patch ds source.
patch_ds() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    patch_xt_offsetof_tree src/php
  fi
}

# Function to move to maxminddb extension source.
patch_maxminddb() {
  if [ -d ext ]; then
    cd ext || return 1
  fi
  [[ "$PHP_VERSION" = "8.6" ]] && patch_xt_offsetof_tree .
}

# Function to patch rdkafka source.
patch_rdkafka() {
  patch_spl_symbols
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    find . -type f -exec sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' {} +
    sed -i 's/EMPTY_SWITCH_DEFAULT_CASE()/default: ZEND_UNREACHABLE()/g' rdkafka.c
    patch_xt_offsetof_tree .
  fi
}

# Function to patch oauth source.
patch_oauth() {
  [[ "$PHP_VERSION" = "7.0" ]] && sed -i 's/php_mt_rand_range(0, 255)/(php_mt_rand() % 256)/g' provider.c
  [[ "$PHP_VERSION" = "8.6" ]] && patch_xt_offsetof_tree .
}

# Function to patch grpc source.
patch_grpc() {
  if [[ "$PHP_VERSION" = "5.6" ]]; then
    local graphcycles str_format_extension float_conversion elf_mem_image
    graphcycles=third_party/abseil-cpp/absl/synchronization/internal/graphcycles.cc
    str_format_extension=third_party/abseil-cpp/absl/strings/internal/str_format/extension.h
    float_conversion=third_party/abseil-cpp/absl/strings/internal/str_format/float_conversion.cc
    elf_mem_image=third_party/abseil-cpp/absl/debugging/internal/elf_mem_image.cc
    sed -i 's/-Wall -Werror /-Wall /' config.m4
    if [ -f "$elf_mem_image" ]; then
      sed -i '/assert(false);  \/\/ invalid VDSO/d' "$elf_mem_image"
    fi
    if [ -f "$graphcycles" ] && ! grep -q '#include <limits>' "$graphcycles"; then
      sed -i 's/#include <array>/#include <array>\n#include <limits>/' "$graphcycles"
    fi
    if [ -f "$str_format_extension" ] && ! grep -q '#include <stdint.h>' "$str_format_extension"; then
      sed -i 's/#include <limits.h>/#include <limits.h>\n#include <stdint.h>/' "$str_format_extension"
    fi
    if [ -f "$float_conversion" ] && ! grep -q '#include <cstdint>' "$float_conversion"; then
      sed -i 's/#include <cmath>/#include <cmath>\n#include <cstdint>/' "$float_conversion"
    fi
  fi
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    # grpc/grpc#41938: add missing inline to silence always_inline warnings.
    sed -i '/^GPR_ATTRIBUTE_ALWAYS_INLINE_FUNCTION$/ {N; s/GPR_ATTRIBUTE_ALWAYS_INLINE_FUNCTION\n    absl::enable_if_t/GPR_ATTRIBUTE_ALWAYS_INLINE_FUNCTION inline\n    absl::enable_if_t/;}' src/core/lib/promise/detail/promise_factory.h
    sed -i 's/GPR_ATTRIBUTE_ALWAYS_INLINE_FUNCTION auto TrySeq/GPR_ATTRIBUTE_ALWAYS_INLINE_FUNCTION inline auto TrySeq/g; s/GPR_ATTRIBUTE_ALWAYS_INLINE_FUNCTION auto TrySeqIter/GPR_ATTRIBUTE_ALWAYS_INLINE_FUNCTION inline auto TrySeqIter/g' src/core/lib/promise/try_seq.h
    sed -i 's/GPR_NO_UNIQUE_ADDRESS union {/union {/' src/core/lib/promise/loop.h
    patch_xt_offsetof_tree .
  fi
}

# Function to patch ssh2 source.
patch_ssh2() {
  if [[ "$PHP_VERSION" =~ 7.[0-2] ]]; then
    sed -i 's/ZSTR_VAL(resource->path)/SSH2_URL_STR(resource->path)/g' ssh2_fopen_wrappers.c
    sed -i 's/zend_string_release(resource->path);/efree(resource->path);/g' ssh2_fopen_wrappers.c
    sed -i 's/resource->path = zend_string_init(path_in_original, strlen(path_in_original), 0);/resource->path = estrdup(path_in_original);/g' ssh2_fopen_wrappers.c
  fi
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/zval_is_true(&zretval)/zend_is_true(\&zretval)/g' ssh2.c
    sed -i 's/zval_dtor(&copyval);/zval_ptr_dtor(\&copyval);/g' ssh2_fopen_wrappers.c
  fi
}

# Function to patch gearman source.
patch_gearman() {
  if [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/zend_exception_get_default()/zend_ce_exception/g' php_gearman.c
  fi
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    find . -type f -exec sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' {} +
    patch_xt_offsetof_tree .
  fi
}

# Function to patch gnupg source.
patch_gnupg() {
  [[ "$PHP_VERSION" = "8.6" ]] && patch_xt_offsetof_tree .
}

# Function to patch mcrypt source.
patch_mcrypt() {
  if [[ "$PHP_VERSION" =~ 8.[2-6] ]]; then
    sed -i 's#ext/standard/php_rand.h#ext/random/php_random.h#g' mcrypt.c
  fi
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i '/#include "php.h"/a #ifndef INI_STR\n#define INI_STR(name) zend_ini_string((name), strlen(name), 0)\n#endif' mcrypt_filter.c
    sed -i '/php_mcrypt_filter,$/a \    NULL,' mcrypt_filter.c
    sed -i \
      -e 's/static php_stream_filter \*php_mcrypt_filter_create(const char \*filtername, zval \*filterparams, uint8_t persistent)/static php_stream_filter *php_mcrypt_filter_create(const char *filtername, zval *filterparams, bool persistent)/' \
      -e 's/php_stream_filter_alloc(&php_mcrypt_filter_ops, data, persistent)/php_stream_filter_alloc(\&php_mcrypt_filter_ops, data, persistent, PSFS_SEEKABLE_NEVER, PSFS_SEEKABLE_NEVER)/' \
      mcrypt_filter.c
  fi
}

# Function to patch http source.
patch_http() {
  sed -i -E ':a;N;$!ba;s#PECL_HAVE_PHP_EXT\(\[(raphf|propro)\], \[\n[[:space:]]*PECL_HAVE_PHP_EXT_HEADER\(\[\1\]\)\n[[:space:]]*\], \[\n[[:space:]]*AC_MSG_ERROR\(\[please install and enable pecl/\1\]\)\n[[:space:]]*\]\)#PECL_HAVE_PHP_EXT_HEADER([\1])#g' config9.m4
  sed -i -E 's#HTTP_HAVE_PHP_EXT\(\[(raphf|propro)\], \[#if true; then#g' config9.m4
  sed -i -E ':a;N;$!ba;s#\n[[:space:]]*\], \[\n[[:space:]]*AC_MSG_ERROR\(\[Please install pecl/(raphf|propro) and activate extension=\1\.\$SHLIB_DL_SUFFIX_NAME in your php\.ini\]\)\n[[:space:]]*\]\)#\n\tfi#g' config9.m4
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    find src -type f -exec sed -i 's/ZEND_RESULT_CODE/zend_result/g; s/zval_dtor/zval_ptr_dtor_nogc/g' {} +
    sed -i 's/ctx->closure.internal_function.arg_info = .*ai_user_handler\[1\];/ctx->closure.internal_function.arg_info = (zend_arg_info *) \&ai_user_handler[1];/g' src/php_http_client_curl_user.c
    sed -i 's#standard/php_lcg.h#random/php_random.h#g' src/php_http_message_body.c src/php_http_misc.c
    sed -i 's/static php_stream_filter \*http_filter_create(const char \*name, zval \*params, uint8_t p)/static php_stream_filter *http_filter_create(const char *name, zval *params, bool p)/g' src/php_http_filter.c
    sed -i '/PHP_HTTP_FILTER_FUNC(/ { N; /\n[[:space:]]*\(PHP_HTTP_FILTER_DTOR(\|NULL,\)/ s/\n/\n\tNULL,\n/ }' src/php_http_filter.c
    sed -i -E 's/php_stream_filter_alloc\(([^,]+), ([^,]+), ([^)]+)\)/php_stream_filter_alloc(\1, \2, \3, PSFS_SEEKABLE_NEVER, PSFS_SEEKABLE_NEVER)/g' src/php_http_filter.c
    patch_xt_offsetof_tree src
  fi
}

# Function to patch pq source.
patch_pq() {
  sed -i 's#PQ_HAVE_PHP_EXT(\[raphf\], \[#if true; then#' config9.m4
  sed -i -E ':a;N;$!ba;s#\n[[:space:]]*\], \[\n[[:space:]]*AC_MSG_ERROR\(\[Please install pecl/raphf and activate extension=raphf\.\$SHLIB_DL_SUFFIX_NAME in your php\.ini\]\)\n[[:space:]]*\]\)#\n\t\tfi#' config9.m4
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    find src -type f -exec sed -i 's/ZEND_RESULT_CODE/zend_result/g; s/zval_dtor/zval_ptr_dtor_nogc/g; s/ZVAL_IS_NULL(\([^)]*\))/Z_TYPE_P(\1) == IS_NULL/g' {} +
    patch_xt_offsetof_tree src
  fi
}

# Function to patch smbclient source.
patch_smbclient() {
  if [[ "$PHP_VERSION" = "5.6" ]]; then
    sed -i 's/"Negative byte count: " ZEND_LONG_FMT/"Negative byte count: %ld"/g' smbclient.c
    sed -i 's/zend_off_t/off_t/g' smb_streams.c
  fi
}

# Function to patch solr source.
patch_solr() {
  sed -i '/^[[:space:]]*done$/,/^[[:space:]]*fi$/ { /^[[:space:]]*fi$/a \\n\tif test -z "$CURL_DIR" && test -r /usr/include/`cc -dumpmachine`/curl/easy.h; then\n\t\tCURL_DIR=/usr\n\t\tCURL_CFLAGS="-I/usr/include/`cc -dumpmachine`"\n\t\tAC_MSG_RESULT(found in /usr/include/`cc -dumpmachine`)\n\tfi
  }' config.m4
  sed -i 's/PHP_ADD_INCLUDE($CURL_DIR\/include)/PHP_EVAL_INCLINE($CURL_CFLAGS)\n    PHP_ADD_INCLUDE($CURL_DIR\/include)/' config.m4
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    find src -type f -exec sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' {} +
    patch_xt_offsetof_tree .
  fi
}

# Function to patch xmlrpc source.
patch_xmlrpc() {
  [[ "$PHP_VERSION" = "8.6" ]] && patch_xt_offsetof_tree .
}

# Function to patch rrd source.
patch_rrd() {
  [[ "$PHP_VERSION" = "5.6" ]] && return 0
  curl -fsSL --retry 5 --retry-all-errors -o rrd-build.patch https://src.fedoraproject.org/rpms/php-pecl-rrd/raw/166ec60/f/rrd-build.patch || return 1
  curl -fsSL --retry 5 --retry-all-errors -o rrd-php85.patch https://src.fedoraproject.org/rpms/php-pecl-rrd/raw/04ac910/f/rrd-php85.patch || return 1
  patch --batch -p1 -i rrd-build.patch || return 1
  patch --batch -p1 -i rrd-php85.patch || return 1
  add_cflags -Wno-incompatible-pointer-types
}

# Function to patch zstd source.
patch_zstd() {
  [[ "$PHP_VERSION" = "8.6" ]] && patch_xt_offsetof_tree .
}

# Function to patch opentelemetry source.
patch_opentelemetry() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/zend_internal_arg_info \*arg_info =/zend_arg_info *arg_info =/' otel_observer.c
    sed -i '/size_t len = strlen(arg_info->name);/d' otel_observer.c
    sed -i '/if (len == ZSTR_LEN(arg_name) &&/ { N; s#if (len == ZSTR_LEN(arg_name) \&\&\n[[:space:]]*!memcmp(arg_info->name, ZSTR_VAL(arg_name), len)) {#if (arg_info->name \&\& zend_string_equals(arg_name, arg_info->name)) {#; }' otel_observer.c
    sed -i \
      -e 's/save_state->prev_exception = EG(prev_exception);/save_state->prev_exception = NULL;/' \
      -e 's/EG(prev_exception) = NULL;//' \
      -e 's/EG(prev_exception) = save_state->prev_exception;//' \
      -e 's/zval_dtor/zval_ptr_dtor_nogc/g' \
      otel_observer.c
  fi
}

# Function to patch protobuf source.
patch_protobuf() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' map.c message.c
  fi
}

# Function to patch raphf source.
patch_raphf() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/ZEND_RESULT_CODE/zend_result/g' src/php_raphf_api.h src/php_raphf_api.c
    sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' src/php_raphf_api.c
  fi
}

# Function to patch uploadprogress source.
patch_uploadprogress() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/INI_BOOL(/zend_ini_bool_literal(/g; s/INI_STR(/zend_ini_string_literal(/g' uploadprogress.c
  fi
}

# Function to patch xlswriter source.
patch_xlswriter() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    find . -type f -exec sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' {} +
    if [[ -f kernel/common.c ]] && ! grep -q 'xlswriter_php_idate' kernel/common.c; then
      sed -i '/lxlsx_datetime timestamp_to_datetime/i\
#if PHP_VERSION_ID >= 80600\
static int xlswriter_php_idate(char format, time_t ts, bool localtime)\
{\
    int result = 0;\
    php_idate(format, ts, localtime, &result);\
    return result;\
}\
#define php_idate(format, ts, localtime) xlswriter_php_idate(format, ts, localtime)\
#endif\
' kernel/common.c
    fi
    patch_xt_offsetof_tree .
  fi
}

# Function to patch uopz source.
patch_uopz() {
  if [[ "$PHP_VERSION" = "7.0" ]]; then
    sed -i 's/static inline uopz_try_addref/static inline void uopz_try_addref/' src/function.c
  fi
  if [[ "$PHP_VERSION" = "8.1" ]]; then
    sed -i 's/PHP_VERSION_ID > 80100/PHP_VERSION_ID >= 80200/' src/function.c
  fi
  if [[ "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]]; then
    curl -fsSL --retry 5 --retry-all-errors -o uopz-pr-185.patch.orig https://patch-diff.githubusercontent.com/raw/krakjoe/uopz/pull/185.patch || return 1
    awk 'BEGIN { skip=0 } index($0, "diff --git a/tests/") == 1 { skip=1 } index($0, "diff --git ") == 1 && index($0, "diff --git a/tests/") != 1 { skip=0 } !skip { print }' uopz-pr-185.patch.orig > uopz-pr-185.patch
    patch --batch -p1 -i uopz-pr-185.patch || return 1
  fi
  if [[ "$PHP_VERSION" = "8.5" || "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/zend_exception_get_default()/zend_ce_exception/g' uopz.c
  fi
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/INI_INT(/zend_ini_long_literal(/g' uopz.c
    sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' src/constant.c
  fi
}

# Function to patch imap source.
patch_imap() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/INI_STR(/zend_ini_string_literal(/g' php_imap.c
    patch_xt_offsetof_tree .
  fi
}

# Function to patch memcache source.
patch_memcache() {
  [[ "$PHP_VERSION" = "5.6" ]] && add_cflags -Wno-incompatible-pointer-types
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

# Function to patch phalcon source.
patch_phalcon() {
  [[ "$PHP_VERSION" = "8.0" ]] && add_cflags -Wno-error=incompatible-pointer-types
  if [[ "$PHP_VERSION" = "7.4" || "$PHP_VERSION" = "8.0" ]]; then
    sed -i 's#ZEPHIR_GLOBAL(orm).resultset_prefetch_records = ZSTR_VAL(zval_get_string(&prefetchRecords));#ZEPHIR_GLOBAL(orm).resultset_prefetch_records = zval_get_string(\&prefetchRecords);#' phalcon.zep.c
    sed -i 's#phalcon_globals->orm.resultset_prefetch_records = ZSTR_VAL(zend_string_init(ZEND_STRL("0"), 0));#phalcon_globals->orm.resultset_prefetch_records = zend_string_init(ZEND_STRL("0"), 0);#' phalcon.zep.c
  fi
  if [[ "$PHP_VERSION" =~ ^8\.[1-4]$ ]]; then
    sed -i 's/# define ZEPHIR_Z_PARAM_ARRAY(dest, dest_ptr)              Z_PARAM_ARRAY(dest)$/# define ZEPHIR_Z_PARAM_ARRAY(dest, dest_ptr)              Z_PARAM_ARRAY(dest_ptr)/' phalcon.zep.c
    sed -i 's/# define ZEPHIR_Z_PARAM_ARRAY_OR_NULL(dest, dest_ptr)      Z_PARAM_ARRAY_OR_NULL(dest)$/# define ZEPHIR_Z_PARAM_ARRAY_OR_NULL(dest, dest_ptr)      Z_PARAM_ARRAY_OR_NULL(dest_ptr)/' phalcon.zep.c
  fi
}

# Function to patch memcached source.
patch_memcached() {
  [[ "$PHP_VERSION" = "8.3" || "$PHP_VERSION" = "8.4" || "$PHP_VERSION" = "8.5" ]] && sed -i "s/#include \"php.h\"/#include <errno.h>\n#include \"php.h\"/" php_memcached.h
  [[ "$PHP_VERSION" = "8.6" ]] && sed -i 's/zval_dtor/zval_ptr_dtor_nogc/g' php_memcached.c
  [[ "$PHP_VERSION" = "8.6" ]] && patch_xt_offsetof_tree .
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
    local file
    grep -rl 'php_hash_bin2hex' . 2>/dev/null | xargs -r sed -i 's/php_hash_bin2hex/zend_bin2hex/g'
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
    patch_xt_offsetof_tree .
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
    patch_xt_offsetof_tree .
  fi
}

# Function to patch mongodb source.
patch_mongodb() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/ZVAL_IS_NULL/Z_ISNULL_P/' src/MongoDB/ServerApi.c
    sed -i 's/zval_is_true/zend_is_true/' src/MongoDB/ServerApi.c
    sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' src/MongoDB/Cursor.c
    patch_xt_offsetof_tree .
  fi
}

# Function to patch apcu source.
patch_apcu() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' apc_cache.c
    sed -i 's/EMPTY_SWITCH_DEFAULT_CASE()/default: ZEND_UNREACHABLE();/g' apc_persist.c
    patch_xt_offsetof_tree .
  fi
}

# Function to patch msgpack source.
patch_msgpack() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    local file
    for file in msgpack.c msgpack_unpack.c; do
      sed -i 's/zval_dtor/zval_ptr_dtor_nogc/' $file
    done
    patch_xt_offsetof_tree .
  fi
}

# Function to patch pspell source.
patch_pspell() {
  if [[ "$PHP_VERSION" = "8.6" ]]; then
    patch_xt_offsetof_tree .
  fi
}
