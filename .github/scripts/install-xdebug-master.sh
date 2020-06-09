install_dir=$1
curl -o /tmp/xdebug.tar.gz -sSL https://github.com/xdebug/xdebug/archive/master.tar.gz
tar xf /tmp/xdebug.tar.gz -C /tmp
(
  cd /tmp/xdebug-master || exit 1
  sudo "$install_dir"/bin/phpize
  sudo ./configure --enable-xdebug --with-php-config="$install_dir"/bin/php-config
  sudo make
  sudo make install
)