# Function to strip debug symbols to external files.
strip_debug() {
  (
    cd "$FAKE_ROOT" || exit 1

    # Export options
    export DH_VERBOSE=1
    export DH_OPTIONS

    # Create files required to run dh_strip.
    cp -a "$GITHUB_WORKSPACE"/config/debian/* debian/
    sed -i "s/PHP_VERSION/$PHP_VERSION/g" debian/control debian/changelog

    # Strip debug symbols.
    dh_strip --dbgsym-migration="php$PHP_VERSION-dbg" || dh_strip
  )
}

# Function to copy stripped debug symbols to the build.
copy_debug_symbols() {
  debug_symbols_dir="$FAKE_ROOT"/debian/.debhelper/php"$PHP_VERSION"/dbgsym-root/usr/lib/debug/.build-id
  if [ -d "$debug_symbols_dir" ]; then
    cp -a "$debug_symbols_dir" "$INSTALL_ROOT"/usr/lib/debug
  fi
}