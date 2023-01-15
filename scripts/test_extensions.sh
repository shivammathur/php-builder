set -e
php -m
extensions=( "amqp" "apcu" "ds" "igbinary" "imagick" "memcache" "memcached" "mongodb" "msgpack" "redis" "xdebug" "sqlsrv" "pdo_sqlsrv" "yaml" )
if [[ "$PHP_VERSION" != "5.6" && "$PHP_VERSION" != "7.0" ]]; then
   extensions+=( "pcov" )
   ln -sf /etc/php/"$PHP_VERSION"/mods-available/pcov.ini /etc/php/"$PHP_VERSION"/cli/conf.d/20-pcov.ini
fi
for extension in "${extensions[@]}"; do
  php -r "if(! extension_loaded(\"$extension\")) {throw new Exception(\"$extension not found\");}"
done
