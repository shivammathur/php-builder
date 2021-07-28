patch_imagick() {
  sed -i 's/spl_ce_Countable/zend_ce_countable/' imagick.c util/checkSymbols.php
}

patch_sqlsrv() {
  cd source/sqlsrv || exit 1
  cp -rf ../shared ./

}

patch_pdo_sqlsrv() {
  cd source/pdo_sqlsrv || exit 1
  cp -rf ../shared ./
}

extension=$1
repo=$2
tag=$3
install_dir=$4
shift 4
params=("$@")
curl -o "/tmp/$extension.tar.gz" -sSL "$repo/archive/$tag.tar.gz"
tar xf "/tmp/$extension.tar.gz" -C /tmp
(
  cd /tmp/"$(basename "$repo")"-"$tag" || exit 1
  patch_"${extension}" 2>/dev/null || true
  "$install_dir"/bin/phpize
  ./configure "--with-php-config=$install_dir/bin/php-config" "${params[@]}"
  make -j"$(nproc)"
  make install
)