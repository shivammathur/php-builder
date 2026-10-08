sudo_php_env() {
  sudo --preserve-env=ASAN_OPTIONS,UBSAN_OPTIONS,ZEND_DONT_UNLOAD_MODULES,USE_ZEND_ALLOC "$@"
}

configure_asan_env() {
  [ -n "${ASAN_OPTIONS:-}" ] || return 1

  fpm_env="/etc/default/php-fpm$PHP_VERSION"
  systemd_env="/etc/systemd/system/php$PHP_VERSION-fpm.service.d/asan-env.conf"
  sudo touch "$fpm_env"
  sudo mkdir -p "${systemd_env%/*}"
  {
    echo "[Service]"
    for name in ASAN_OPTIONS UBSAN_OPTIONS ZEND_DONT_UNLOAD_MODULES USE_ZEND_ALLOC; do
      value="${!name-}"
      [ "$name" != USE_ZEND_ALLOC ] || value="${USE_ZEND_ALLOC-1}"
      if [ -n "$value" ]; then
        sudo sed -i "/^export $name=/d" "$fpm_env"
        printf 'export %s=%s\n' "$name" "$value" | sudo tee -a "$fpm_env" >/dev/null
      elif [ "$name" != USE_ZEND_ALLOC ]; then
        continue
      fi
      printf 'Environment="%s=%s"\n' "$name" "$value"
    done
  } | sudo tee "$systemd_env" >/dev/null
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
