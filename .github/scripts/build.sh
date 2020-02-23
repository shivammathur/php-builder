LOG() {
  time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$time"" > ""$1" >>build.log
}

release=$(lsb_release -r -s)
install_dir=~/php/"$PHP_VERSION"
action_dir=$(pwd)
(
  cd ~ || exit
  git clone git://github.com/php-build/php-build
  cd php-build || exit
  sudo ./install.sh
  cp -rf "$action_dir"/.github/scripts/default_configure_options ./share/php-build/default_configure_options
)
sudo mkdir -p ~/php
sudo chmod -R 777 ~/php
php-build -i production master "$install_dir"
sudo chmod 777 "$install_dir"/etc/php.ini
(
  echo "date.timezone=UTC"
  echo "opcache.jit_buffer_size=256M"
  echo "opcache.jit=1235"
  echo "pcre.jit=1"
) >>"$install_dir"/etc/php.ini
sudo mkdir -p /usr/local/ssl
sudo wget -O /usr/local/ssl/cert.pem https://curl.haxx.se/ca/cacert.pem
curl -fsSL --retry 20 -O https://pear.php.net/go-pear.phar
sudo chmod a+x ./.github/scripts/install-pear.sh
./.github/scripts/install-pear.sh "$install_dir"
rm go-pear.phar
sudo "$install_dir"/bin/pear config-set php_ini "$install_dir"/etc/php.ini system
sudo "$install_dir"/bin/pear config-set auto_discover 1
sudo "$install_dir"/bin/pear channel-update pear.php.net
sudo ln -sv "$install_dir"/sbin/php-fpm "$install_dir"/bin/php-fpm
sudo ln -sf "$install_dir"/bin/* /usr/bin/
sudo ln -sf "$install_dir"/etc/php.ini /etc/php.ini
(
  cd "$install_dir"/.. || exit
  sudo XZ_OPT=-9 tar cfJ php_"$PHP_VERSION"+ubuntu"$release".tar.xz "$PHP_VERSION"
  shopt -s nullglob
  for f in *.xz; do
    sha256sum "$f" >"${f}".sha256sum.txt
  done
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
  curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -X DELETE https://api.bintray.com/content/"$BINTRAY_USER"/"$BINTRAY_REPO"/php_"$PHP_VERSION"+ubuntu"$release".tar.xz || true
  curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -T php_"$PHP_VERSION"+ubuntu"$release".tar.xz https://api.bintray.com/content/shivammathur/php/"$PHP_VERSION"-linux/"$PHP_VERSION"+ubuntu"$release"/php_"$PHP_VERSION"+ubuntu"$release".tar.xz || true
  curl --user "$BINTRAY_USER":"$BINTRAY_KEY" -X POST https://api.bintray.com/content/"$BINTRAY_USER"/"$BINTRAY_REPO"/"$PHP_VERSION"-linux/"$PHP_VERSION"+ubuntu"$release"/publish || true
)

git config --local user.email "$GITHUB_EMAIL"
git config --local user.name "$GITHUB_NAME"
git stash
git pull -f https://"$GITHUB_USER":"$GITHUB_TOKEN"@github.com/"$GITHUB_REPOSITORY".git HEAD:master
git stash apply
LOG "ubuntu$release build updated"
git add .
git commit -m "ubuntu$release build updated"
git push -f https://"$GITHUB_USER":"$GITHUB_TOKEN"@github.com/"$GITHUB_REPOSITORY".git HEAD:master --follow-tags
