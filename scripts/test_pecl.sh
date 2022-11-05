if [ "$PHP_VERSION" = "5.6" ]; then
  sudo pecl install -f psr-0.6.0
elif [[ "$PHP_VERSION" =~ 7.[0-2]$ ]]; then
  sudo pecl install -f psr-1.1.0
else
  sudo pecl install -f psr
fi
php -m | grep -q psr || exit 1
