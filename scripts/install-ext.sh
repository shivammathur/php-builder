patch_imagick() {
  sed -i 's/spl_ce_Countable/zend_ce_countable/' imagick.c util/checkSymbols.php
}

extension=$1
prefix=$2
repo=$3
tag=${4:-master}
install_dir=$5
params=${6:-}
shift 6
args=("$@")
curl -o "/tmp/$extension.tar.gz" -sSL "https://github.com/$repo/archive/$tag.tar.gz"
tar xf "/tmp/$extension.tar.gz" -C /tmp
(
  cd "/tmp/$(basename "$repo")-$tag" || exit 1
  patch_"${extension}" 2>/dev/null || true
  sudo "$install_dir"/bin/phpize
  sudo ./configure "$params" "--with-php-config=$install_dir/bin/php-config" "${args[@]}"
  sudo make -j"$(nproc)"
  sudo make install
  echo "$prefix=$extension" | sudo tee -a "$install_dir"/etc/conf.d/30-"$extension".ini
)