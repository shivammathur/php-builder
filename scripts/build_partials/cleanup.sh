# Function to cleanup files not required in the build
cleanup() {
  # Cleanup
  PHP_API="$(php-config"$PHP_VERSION" --phpapi)"
  rm -rf "$INSTALL_ROOT"/etc/pear.conf \
         "$INSTALL_ROOT"/.channels \
         "$INSTALL_ROOT"/.registry \
         "$INSTALL_ROOT"/.filemap \
         "$INSTALL_ROOT"/.lock \
         "$INSTALL_ROOT"/.depdb* \
         "$INSTALL_ROOT"/usr/bin/pear* \
         "$INSTALL_ROOT"/usr/bin/pecl* \
         "$INSTALL_ROOT"/usr/share/php/.filemap \
         "$INSTALL_ROOT"/usr/share/php/.lock \
         "$INSTALL_ROOT"/usr/share/php/.depdb* \
         "$INSTALL_ROOT"/usr/share/php/*.php \
         "$INSTALL_ROOT"/usr/share/php/.registry \
         "$INSTALL_ROOT"/usr/share/php/.channels \
         "$INSTALL_ROOT"/usr/share/php/doc \
         "$INSTALL_ROOT"/usr/share/php/Archive \
         "$INSTALL_ROOT"/usr/share/php/Console \
         "$INSTALL_ROOT"/usr/share/php/Structures \
         "$INSTALL_ROOT"/usr/share/php/test \
         "$INSTALL_ROOT"/usr/share/php/XML \
         "$INSTALL_ROOT"/usr/share/php/OS \
         "$INSTALL_ROOT"/usr/share/php/PEAR \
         "$INSTALL_ROOT"/usr/share/php/data \
         "$INSTALL_ROOT"/usr/share/php/docs/* \
         "$INSTALL_ROOT"/usr/share/php/tests/* \
	       "$INSTALL_ROOT"/usr/lib/php/"$PHP_API"/config.guess \
         "$INSTALL_ROOT"/usr/lib/php/"$PHP_API"/config.sub \
         "$INSTALL_ROOT"/usr/lib/php/"$PHP_API"/libtool.m4 \
         "$INSTALL_ROOT"/usr/lib/php/"$PHP_API"/pkg.m4 \
         "$INSTALL_ROOT"/usr/lib/php/"$PHP_API"/ltmain.sh \
         "$INSTALL_ROOT"/usr/lib/php/"$PHP_API"/shtool \
         "$INSTALL_ROOT"/usr/include/php/"$PHP_API"/ext/gd/libgd \
         "$INSTALL_ROOT"/usr/include/php/"$PHP_API"/ext/pcre/pcre2lib \
         "$INSTALL_ROOT"/usr/lib/debug
}
