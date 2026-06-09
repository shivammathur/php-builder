sudo_php_env() {
  sudo env \
    ASAN_OPTIONS="${ASAN_OPTIONS:-}" \
    UBSAN_OPTIONS="${UBSAN_OPTIONS:-}" \
    ZEND_DONT_UNLOAD_MODULES="${ZEND_DONT_UNLOAD_MODULES:-}" \
    "$@"
}

if [ "$PHP_VERSION" = "5.6" ]; then
  sudo_php_env pecl install -f psr-0.6.0
elif [[ "$PHP_VERSION" =~ 7.[0-2]$ ]]; then
  sudo_php_env pecl install -f psr-1.1.0
else
  sudo_php_env pecl install -f psr
fi
php -m | grep -q psr || exit 1
