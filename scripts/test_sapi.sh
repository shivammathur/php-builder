sudo_php_env() {
  sudo --preserve-env=ASAN_OPTIONS,UBSAN_OPTIONS,ZEND_DONT_UNLOAD_MODULES,USE_ZEND_ALLOC "$@"
}

run_switch_sapi() {
  if [ -n "${ASAN_OPTIONS:-}" ] && command -v timeout >/dev/null 2>&1; then
    sudo_php_env timeout 120 switch_sapi -v "$PHP_VERSION" -s "$1"
  else
    sudo_php_env switch_sapi -v "$PHP_VERSION" -s "$1"
  fi
}

sudo mkdir -p /var/www/html
sudo rm -rf /var/www/html/index.html
printf "<?php echo current(explode('-', php_sapi_name())).':'.strtolower(current(explode('/', \$_SERVER['SERVER_SOFTWARE']))).\"\n\";" | sudo tee /var/www/html/index.php >/dev/null
for sapi in apache2handler:apache fpm:apache cgi:apache fpm:nginx; do
  run_switch_sapi "$sapi"
  resp="$(curl -fsS --connect-timeout 5 --max-time 30 http://localhost)" || exit 1
  [ "$sapi" != "$resp" ] && exit 1 || echo "$resp"
done
