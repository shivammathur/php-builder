configure_phpbuild() {
  cp /usr/local/share/php-build/default_configure_options /usr/local/share/php-build/default_configure_options.bak
  if [ "$new_version" != "nightly" ]; then
    cp "$action_dir"/config/definitions/stable /usr/local/share/php-build/definitions/"$PHP_VERSION"
    sed -i "s/phpsrctag/$new_version/" /usr/local/share/php-build/definitions/"$PHP_VERSION"
    branch="$new_version"
  else
    cp "$action_dir"/config/definitions/"$PHP_VERSION" /usr/local/share/php-build/definitions/
  fi
  patches_dir="$action_dir"/config/patches
  [ -d "$patches_dir" ] && find "$patches_dir" -name '*' -exec cp "{}" /usr/local/share/php-build/patches \;
  sed -i "s|PREFIX|$install_dir|" /usr/local/share/php-build/definitions/"$PHP_VERSION"
}

setup_phpbuild() {
  echo "::group::php-build"
  git clone git://github.com/php-build/php-build ~/php-build
  ~/php-build/install.sh
  configure_phpbuild
  echo "::endgroup::"
}

setup_pear() {
  echo "::group::pear"
  curl -fsSL --retry "$tries" -o /usr/local/ssl/cert.pem https://curl.se/ca/cacert.pem
  curl -fsSL --retry "$tries" -O https://raw.githubusercontent.com/pear/pearweb_phars/master/go-pear.phar
  chmod a+x scripts/install-pear.expect
  scripts/install-pear.expect "$install_dir"
  rm go-pear.phar
  "$install_dir"/bin/pear config-set php_ini "$install_dir"/etc/php.ini system
  "$install_dir"/bin/pear channel-update pear.php.net
  echo "::endgroup::"
}

enable_extension() {
  extension=$1
  prefix=$2
  sed -i "/$extension/d" "$install_dir"/etc/php.ini
  if [ -e "$ext_dir/$extension.so" ]; then
    echo "$prefix=$extension.so" | tee -a "$install_dir"/etc/conf.d/20-"$extension".ini >/dev/null 2>&1
  fi
}

setup_extensions() {
  ext_dir="$("$install_dir"/bin/php -i | grep "extension_dir => /" | sed -e "s|.*=> s*||")"
  while read -r extension_config; do
    type=$(echo "$extension_config" | cut -d ' ' -f 1)
    extension=$(echo "$extension_config" | cut -d ' ' -f 2)
    prefix=$(echo "$extension_config" | cut -d ' ' -f 3)
    echo "::group::$extension"
    if [ "$type" = "pecl" ]; then
      yes '' 2>/dev/null | "$install_dir"/bin/pecl install -f "$extension"
    elif [ "$type" = "git" ]; then
      repo=$(echo "$extension_config" | cut -d ' ' -f 4)
      tag=$(echo "$extension_config" | cut -d ' ' -f 5)
      IFS=' ' read -r -a args <<<"$(echo "$extension_config" | cut -d ' ' -f 6-)"
      bash scripts/install-ext.sh "$extension" "$repo" "$tag" "$install_dir" "${args[@]}"
    fi
    enable_extension "$extension" "$prefix"
    echo "::endgroup::"
  done < "$action_dir"/config/extensions/"$PHP_VERSION"
  enable_extension intl extension

  # Disable pcov by default as it conflicts with JIT.
  rm "$install_dir"/etc/conf.d/20-pcov.ini
}

build_php() {
  echo "::group::$1"
  export CFLAGS="-Wno-missing-field-initializers $CFLAGS"
  export CXXFLAGS="-Wno-missing-field-initializers $CXXFLAGS"
  if ! php-build -v -i production "$PHP_VERSION" "$install_dir"; then
    echo 'Failed to build PHP'
    exit 1
  fi
  echo "::endgroup::"
}

configure_apache_fpm_opts() {
  sed -i "/cgi/d" /usr/local/share/php-build/default_configure_options
  sed -i '1iconfigure_option "--with-apxs2" "/usr/bin/apxs2"' /usr/local/share/php-build/definitions/"$PHP_VERSION"
  echo "--enable-cgi" | tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  echo "--enable-fpm" | tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  echo "--with-fpm-systemd" | tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  echo "--with-fpm-user=www-data" | tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  echo "--with-fpm-group=www-data" | tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
}

configure_apache_fpm() {
  ln -s "$install_dir"/sbin/php-fpm "$install_dir"/bin/php-fpm
  ln -s "$install_dir"/bin/php-cgi "$install_dir"/usr/lib/cgi-bin/php"$PHP_VERSION"
  mv "$install_dir"/etc/init.d/php-fpm "$install_dir"/etc/init.d/php"$PHP_VERSION"-fpm.orig
  mv "$install_dir"/usr/lib/apache2/modules/libphp.so "$install_dir"/usr/lib/apache2/modules/libphp"$PHP_VERSION".so
  sed -Ei -e "s|^listen = .*|listen = /run/php/php$PHP_VERSION-fpm.sock|" -e 's|;listen.owner.*|listen.owner = www-data|' -e 's|;listen.group.*|listen.group = www-data|' -e 's|;listen.mode.*|listen.mode = 0660|' "$install_dir"/etc/php-fpm.d/www.conf
  sed -i "s/PHP_MAJOR/${PHP_VERSION/%.*}/g" config/php-fpm.conf
  for file in default_nginx fpm.init fpm.service php-cgi.conf php-fpm.conf php.load; do
    sed -i "s/PHP_VERSION/$PHP_VERSION/g" config/"$file"
  done
  sed -i "s/NO_DOT/${PHP_VERSION/./}/g" config/fpm.service
  sed -i "s/PHP_VERSION/$PHP_VERSION/g" scripts/switch_sapi
  cp -fp config/fpm.tmpfile "$install_dir"/usr/lib/tmpfiles.d/php"$PHP_VERSION"-fpm.conf
  cp -fp config/fpm.init "$install_dir"/etc/init.d/php"$PHP_VERSION"-fpm && chmod a+x "$install_dir"/etc/init.d/php"$PHP_VERSION"-fpm
  cp -fp config/fpm.service "$install_dir"/etc/systemd/system/php"$PHP_VERSION"-fpm.service
  cp -fp scripts/php-fpm-socket-helper scripts/switch_sapi "$install_dir"/bin/ && chmod -R a+x "$install_dir"/bin
  sed -Ei -e "s|;pid.*|pid = /run/php/php$PHP_VERSION-fpm.pid|" -e "s|;error_log.*|error_log = /var/log/php$PHP_VERSION-fpm.log|" "$install_dir"/etc/php-fpm.conf
  cp -fp config/php.conf "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".conf
  cp -fp config/php.load "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".load
  cp -fp config/php-cgi.conf "$install_dir"/etc/apache2/conf-available/php"$PHP_VERSION"-cgi.conf
  cp -fp config/php-fpm.conf "$install_dir"/etc/apache2/conf-available/php"$PHP_VERSION"-fpm.conf
  cp -fp config/default_apache "$install_dir"/etc/apache2/sites-available/000-default.conf
  cp -fp config/default_nginx "$install_dir"/etc/nginx/sites-available/default
}

build_apache_fpm() {
  cp /usr/local/share/php-build/default_configure_options.bak /usr/local/share/php-build/default_configure_options
  mkdir -p "$install_dir" "$install_dir"/"$(apxs -q SYSCONFDIR)"/mods-available "$install_dir"/"$(apxs -q SYSCONFDIR)"/sites-available "$install_dir"/etc/nginx/sites-available "$install_dir"/"$(apxs -q SYSCONFDIR)"/conf-available "$install_dir"/usr/lib/cgi-bin "$install_dir"/usr/lib/tmpfiles.d /usr/local/ssl /lib/systemd/system /usr/lib/cgi-bin
  chmod -R 777 "$install_dir" /usr/local/php /usr/local/ssl /usr/include/apache2 /usr/lib/apache2 /etc/apache2/ /var/lib/apache2 /var/log/apache2
  basename "$(curl -sL https://api.github.com/repos/php/php-src/commits/"$branch" | jq -r .commit.url)" | tee "$install_dir/COMMIT" >/dev/null 2>&1
  export PHP_BUILD_APXS="/usr/bin/apxs2"
  configure_apache_fpm_opts
  build_php apache-fpm
  configure_apache_fpm
  mv "$install_dir" "$install_dir-fpm"
}

build_embed() {
  mkdir -p "$install_dir"
  chmod -R 777 "$install_dir"
  cp /usr/local/share/php-build/default_configure_options.bak /usr/local/share/php-build/default_configure_options
  sed -i "/apxs2/d" /usr/local/share/php-build/definitions/"$PHP_VERSION" || true
  sed -i "/fpm/d" /usr/local/share/php-build/default_configure_options || true
  sed -i "/cgi/d" /usr/local/share/php-build/default_configure_options || true
  echo "--enable-embed=shared" | tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  build_php embed
  mv "$install_dir" "$install_dir-embed"
}

merge_sapi() {
  mv "$install_dir-fpm" "$install_dir"
  cp "$install_dir-embed/lib/libphp.so" "$install_dir/usr/lib/libphp$PHP_VERSION.so"
  sed -i 's/php_sapis=" apache2handler cli fpm phpdbg cgi"/php_sapis=" apache2handler cli fpm phpdbg cgi embed"/' "$install_dir"/bin/php-config
  cp -a "$install_dir-embed/include/php/sapi" "$install_dir/include/php"
}

configure_php() {
  setup_pear
  setup_extensions
  ln -sf "$install_dir"/bin/* /usr/bin/
  ln -sf "$install_dir"/etc/php.ini /etc/php.ini
  chmod 777 "$install_dir"/etc/php.ini
  (
    echo "date.timezone=UTC"
    echo "memory_limit=-1"
  ) >>"$install_dir"/etc/php.ini
  cp -fp "$install_dir"/etc/init.d/php"$PHP_VERSION"-fpm /etc/init.d/
  cp -fp "$install_dir"/etc/systemd/system/php"$PHP_VERSION"-fpm.service /lib/systemd/system/
  cp -fp "$install_dir"/usr/lib/cgi-bin/php"$PHP_VERSION" /usr/lib/cgi-bin/
  cp -fp "$install_dir"/usr/lib/apache2/modules/libphp"$PHP_VERSION".so /usr/lib/apache2/modules/
  cp -fp "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".load /etc/apache2/mods-available/php"$PHP_VERSION".load
  cp -fp "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".conf /etc/apache2/mods-available/
  cp -fp "$install_dir"/etc/apache2/conf-available/php"$PHP_VERSION"-*.conf /etc/apache2/conf-available/
  a2dismod php >/dev/null 2>&1
}

package() {
  (
    echo "::group::package"
    zstd -V
    cd "$install_dir"/.. || exit
    echo "Creating Package using XZ"
    XZ_OPT=-e9 tar cfJ "php_$PHP_VERSION+$ID$VERSION_ID.tar.xz" "$PHP_VERSION"
    echo "Creating Package using ZSTD"
    tar cf - "$PHP_VERSION" | zstd -22 -T0 --ultra > "php_$PHP_VERSION+$ID$VERSION_ID.tar.zst"
    echo "::endgroup::"
  )
}

check_stable() {
  if [[ "$GITHUB_MESSAGE" != *build-all* ]]; then
    if [ "$new_version" = "$existing_version" ]; then
      (
        mkdir -p "$install_dir"
        cd "$install_dir"/.. || exit
        curl -fSL --retry "$tries" -O "$github/php_$PHP_VERSION+$ID$VERSION_ID.tar.xz"
        curl -fSL --retry "$tries" -O "$github/php_$PHP_VERSION+$ID$VERSION_ID.tar.zst"
        ls -la
      )
      echo "$new_version" exists
      exit 0
    fi
  fi
  if [ "$new_version" = "" ]; then
    new_version='nightly'
  fi
}

. /etc/os-release
install_dir=/usr/local/php/"$PHP_VERSION"
action_dir=$(pwd)
tries=10
branch=master
github="https://github.com/${GITHUB_REPOSITORY:?}/releases/download/builds"
existing_version=$(curl -sL "$github"/php"$PHP_VERSION".log)
new_version=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($PHP_VERSION.[0-9]+)" | head -n 1)
check_stable
setup_phpbuild
build_embed
build_apache_fpm
merge_sapi
configure_php
package
