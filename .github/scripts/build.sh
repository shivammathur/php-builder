build_log() {
  time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$time"" > ""$1" >>build.log
}

setup_phpbuild() {
  (
    cd ~ || exit
    git clone git://github.com/php-build/php-build
    cd php-build || exit
    sudo ./install.sh
    sudo cp -rf "$action_dir"/.github/scripts/master /usr/local/share/php-build/definitions/master
  )
}

setup_pear() {
  sudo curl -fsSL --retry "$tries" -o /usr/local/ssl/cert.pem https://curl.haxx.se/ca/cacert.pem
  sudo curl -fsSL --retry "$tries" -O https://pear.php.net/go-pear.phar
  sudo chmod a+x .github/scripts/install-pear.expect
  .github/scripts/install-pear.expect "$install_dir"
  rm go-pear.phar
  sudo "$install_dir"/bin/pear config-set php_ini "$install_dir"/etc/php.ini system
  sudo "$install_dir"/bin/pear channel-update pear.php.net
}

setup_coverage() {
  sudo "$install_dir"/bin/pecl install -f pcov
  sudo sed -i "/pcov/d" "$install_dir"/etc/php.ini
  sudo chmod a+x .github/scripts/install-xdebug-master.sh
  .github/scripts/install-xdebug-master.sh "$install_dir"
}

build_php() {
  if ! php-build -v -i production master "$install_dir"; then
    echo 'Failed to build PHP'
    exit 1
  fi

  sudo chmod 777 "$install_dir"/etc/php.ini
  (
    echo "date.timezone=UTC"
    echo "memory_limit=-1"
    echo "opcache.jit_buffer_size=256M"
    echo "opcache.jit=1235"
    echo "pcre.jit=1"
  ) >>"$install_dir"/etc/php.ini
  setup_pear
  setup_coverage
  sudo ln -sv "$install_dir"/sbin/php-fpm "$install_dir"/bin/php-fpm
  sudo ln -sf "$install_dir"/bin/* /usr/bin/
  sudo ln -sf "$install_dir"/etc/php.ini /etc/php.ini
}

bintray_create_package() {
  curl \
  --user "$BINTRAY_USER":"$BINTRAY_KEY" \
  --header "Content-Type: application/json" \
  --data " \
{\"name\": \"$PHP_VERSION-linux\", \
\"vcs_url\": \"$GITHUB_REPOSITORY\", \
\"licenses\": [\"MIT\"], \
\"public_download_numbers\": true, \
\"public_stats\": true \
}" \
  https://api.bintray.com/packages/"$BINTRAY_USER"/"$BINTRAY_REPO" || true
}

build_and_ship() {
  (
    curl -sSLO http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-10/gcc-10-base_10-20200411-0ubuntu1_amd64.deb
    curl -sSLO http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-10/libgcc-s1_10-20200411-0ubuntu1_amd64.deb
    curl -sSLO http://archive.ubuntu.com/ubuntu/pool/universe/libz/libzstd/zstd_1.4.4+dfsg-3_amd64.deb
    sudo DEBIAN_FRONTEND=noninteractive dpkg -i --force-conflicts ./*.deb
    rm -rf ./*.deb
    zstd -V
    cd "$install_dir"/.. || exit
    sudo XZ_OPT=-e9 tar cfJ php_"$PHP_VERSION"+ubuntu"$release".tar.xz "$PHP_VERSION"
    sudo tar cf - "$PHP_VERSION" | zstd -22 -T0 --ultra > php_"$PHP_VERSION"+ubuntu"$release".tar.zst
    curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -X DELETE https://api.bintray.com/content/"$BINTRAY_USER"/"$BINTRAY_REPO"/php_"$PHP_VERSION"+ubuntu"$release".tar.xz || true
    curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -X DELETE https://api.bintray.com/content/"$BINTRAY_USER"/"$BINTRAY_REPO"/php_"$PHP_VERSION"+ubuntu"$release".tar.zst || true
    curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -T php_"$PHP_VERSION"+ubuntu"$release".tar.xz https://api.bintray.com/content/shivammathur/php/"$PHP_VERSION"-linux/"$PHP_VERSION"+ubuntu"$release"/php_"$PHP_VERSION"+ubuntu"$release".tar.xz || true
    curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -T php_"$PHP_VERSION"+ubuntu"$release".tar.zst https://api.bintray.com/content/shivammathur/php/"$PHP_VERSION"-linux/"$PHP_VERSION"+ubuntu"$release"/php_"$PHP_VERSION"+ubuntu"$release".tar.zst || true
    curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -X POST https://api.bintray.com/content/"$BINTRAY_USER"/"$BINTRAY_REPO"/"$PHP_VERSION"-linux/"$PHP_VERSION"+ubuntu"$release"/publish || true
  )
}

push_log() {
  git config --local user.email "$GITHUB_EMAIL"
  git config --local user.name "$GITHUB_NAME"
  git stash
  git pull -f https://"$GITHUB_USER":"$GITHUB_TOKEN"@github.com/"$GITHUB_REPOSITORY".git HEAD:master
  git stash apply
  build_log "ubuntu$release build updated"
  git add .
  git commit -m "ubuntu$release build updated"
  git push -f https://"$GITHUB_USER":"$GITHUB_TOKEN"@github.com/"$GITHUB_REPOSITORY".git HEAD:master --follow-tags
}

sudo mkdir -m777 -p /usr/local/php /usr/local/ssl
release=$(lsb_release -r -s)
install_dir=/usr/local/php/"$PHP_VERSION"
action_dir=$(pwd)
tries=10

setup_phpbuild
build_php
bintray_create_package
build_and_ship
push_log
