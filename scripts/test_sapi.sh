sudo mkdir -p /var/www/html
sudo rm -rf /var/www/html/index.html
printf "<?php echo current(explode('-', php_sapi_name())).':'.strtolower(current(explode('/', \$_SERVER['SERVER_SOFTWARE']))).\"\n\";" | sudo tee /var/www/html/index.php >/dev/null
for sapi in apache2handler:apache fpm:apache cgi:apache fpm:nginx; do
  sudo switch_sapi -v "$PHP_VERSION" -s "$sapi"
  resp=""
  for _ in $(seq 1 20); do
    resp="$(curl -fsS --max-time 5 http://localhost 2>/dev/null || true)"
    [ -n "$resp" ] && break
    sleep 1
  done
  [ "$sapi" != "$resp" ] && exit 1 || echo "$resp"
done
