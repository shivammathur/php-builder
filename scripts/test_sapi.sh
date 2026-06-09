sudo_php_env() {
  sudo env \
    ASAN_OPTIONS="${ASAN_OPTIONS:-}" \
    UBSAN_OPTIONS="${UBSAN_OPTIONS:-}" \
    ZEND_DONT_UNLOAD_MODULES="${ZEND_DONT_UNLOAD_MODULES:-}" \
    LD_PRELOAD="${LD_PRELOAD:-}" \
    "$@"
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
  } | sudo tee "$file" >/dev/null
}

set_asan_lib() {
  [ -z "${LD_PRELOAD:-}" ] || return
  if command -v gcc >/dev/null 2>&1; then
    asan_lib="$(gcc -print-file-name=libasan.so)"
    [ -f "$asan_lib" ] && export LD_PRELOAD="$asan_lib" && return
  fi
  if command -v php >/dev/null 2>&1; then
    asan_lib="$(ldd "$(command -v php)" 2>/dev/null | awk '/libasan/ {print $3; exit}')"
    [ -f "$asan_lib" ] && export LD_PRELOAD="$asan_lib" && return
  fi
  asan_lib="$(find /usr/lib/gcc -name libasan.so -print -quit 2>/dev/null)"
  [ -f "$asan_lib" ] && export LD_PRELOAD="$asan_lib"
}

configure_asan_env() {
  [ -n "${ASAN_OPTIONS:-}" ] || return 1
  set_asan_lib

  fpm_env="/etc/default/php-fpm$PHP_VERSION"
  write_env "$fpm_env" ASAN_OPTIONS "$ASAN_OPTIONS"
  write_env "$fpm_env" UBSAN_OPTIONS "${UBSAN_OPTIONS:-}"
  write_env "$fpm_env" ZEND_DONT_UNLOAD_MODULES "${ZEND_DONT_UNLOAD_MODULES:-}"
  write_systemd_env "php$PHP_VERSION-fpm.service"
  [ -d /run/systemd/system ] && sudo systemctl daemon-reload 2>/dev/null || true

  apache_env="/etc/apache2/envvars"
  if [ -f "$apache_env" ]; then
    write_env "$apache_env" ASAN_OPTIONS "$ASAN_OPTIONS"
    write_env "$apache_env" UBSAN_OPTIONS "${UBSAN_OPTIONS:-}"
    write_env "$apache_env" ZEND_DONT_UNLOAD_MODULES "${ZEND_DONT_UNLOAD_MODULES:-}"
    write_env "$apache_env" LD_PRELOAD "${LD_PRELOAD:-}"
    {
      [ -n "${ASAN_OPTIONS:-}" ] && echo "PassEnv ASAN_OPTIONS"
      [ -n "${UBSAN_OPTIONS:-}" ] && echo "PassEnv UBSAN_OPTIONS"
      [ -n "${ZEND_DONT_UNLOAD_MODULES:-}" ] && echo "PassEnv ZEND_DONT_UNLOAD_MODULES"
      [ -n "${LD_PRELOAD:-}" ] && echo "PassEnv LD_PRELOAD"
    } | sudo tee /etc/apache2/conf-available/php-asan-env.conf >/dev/null
    sudo a2enconf php-asan-env >/dev/null 2>&1 || true
  fi
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
asan_env_configured=
for sapi in apache2handler:apache fpm:apache cgi:apache fpm:nginx; do
  if [ -z "$asan_env_configured" ] && configure_asan_env; then
    asan_env_configured=1
    run_switch_sapi "$sapi" || true
    configure_asan_env
  fi
  run_switch_sapi "$sapi"
  resp="$(curl -s http://localhost)"
  [ "$sapi" != "$resp" ] && exit 1 || echo "$resp"
done
