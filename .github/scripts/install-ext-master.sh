extension=$1
repo=$2
install_dir=$3
params=${4:-}
curl -o "/tmp/$extension.tar.gz" -sSL "https://github.com/$repo/archive/master.tar.gz"
tar xf "/tmp/$extension.tar.gz" -C /tmp
(
  cd "/tmp/$extension-master" || exit 1
  sudo "$install_dir/bin/phpize"
  sudo ./configure "$params" "--with-php-config=$install_dir/bin/php-config"
  sudo make
  sudo make install
)