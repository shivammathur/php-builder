sudo_php_env() {
  sudo --preserve-env=ASAN_OPTIONS,UBSAN_OPTIONS,ZEND_DONT_UNLOAD_MODULES,USE_ZEND_ALLOC "$@"
}

write_env() {
  file=$1
  name=$2
  value=$3
  [ -n "$value" ] || return
  sudo touch "$file"
  sudo sed -i "/^export $name=/d" "$file"
  printf "export %s=%s\n" "$name" "$value" | sudo tee -a "$file" >/dev/null
}

write_systemd_env() {
  service=$1
  file="/etc/systemd/system/$service.d/asan-env.conf"
  sudo mkdir -p "${file%/*}"
  {
    echo "[Service]"
    [ -n "${ASAN_OPTIONS:-}" ] && printf 'Environment="%s=%s"\n' ASAN_OPTIONS "$ASAN_OPTIONS"
    [ -n "${UBSAN_OPTIONS:-}" ] && printf 'Environment="%s=%s"\n' UBSAN_OPTIONS "$UBSAN_OPTIONS"
    [ -n "${ZEND_DONT_UNLOAD_MODULES:-}" ] && printf 'Environment="%s=%s"\n' ZEND_DONT_UNLOAD_MODULES "$ZEND_DONT_UNLOAD_MODULES"
    printf 'Environment="%s=%s"\n' USE_ZEND_ALLOC "${USE_ZEND_ALLOC-1}"
  } | sudo tee "$file" >/dev/null
}

configure_asan_env() {
  [ -n "${ASAN_OPTIONS:-}" ] || return 1

  fpm_env="/etc/default/php-fpm$PHP_VERSION"
  write_env "$fpm_env" ASAN_OPTIONS "$ASAN_OPTIONS"
  write_env "$fpm_env" UBSAN_OPTIONS "${UBSAN_OPTIONS:-}"
  write_env "$fpm_env" ZEND_DONT_UNLOAD_MODULES "${ZEND_DONT_UNLOAD_MODULES:-}"
  write_env "$fpm_env" USE_ZEND_ALLOC "${USE_ZEND_ALLOC-1}"
  write_systemd_env "php$PHP_VERSION-fpm.service"
  [ -d /run/systemd/system ] && sudo systemctl daemon-reload 2>/dev/null || true
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
configure_asan_env || true
for sapi in apache2handler:apache fpm:apache cgi:apache fpm:nginx; do
  run_switch_sapi "$sapi"
  resp="$(curl -fsS --connect-timeout 5 --max-time 30 http://localhost)" || exit 1
  [ "$sapi" != "$resp" ] && exit 1 || echo "$resp"
done
