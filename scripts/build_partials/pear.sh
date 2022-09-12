# Function to configure pear.
configure_pear() {
  echo "::group::configure_pear"

  # Set pear channel.
  "$INSTALL_ROOT"/usr/bin/pear update-channels
  echo "::endgroup::"
}

# Function to setup pear.
setup_pear() {
  echo "::group::setup_pear"
  mkdir -p /usr/local/ssl

  # Fetch certificate keychain from cURL.
  curl -o /usr/local/ssl/cert.pem -sL https://curl.se/ca/cacert.pem

  # Fetch pear installer and install it in INSTALL_ROOT.
  curl -OsL https://raw.githubusercontent.com/pear/pearweb_phars/master/install-pear-nozlib.phar
  enable_extension xml extension
  INSTALL_ROOT="$INSTALL_ROOT" php install-pear-nozlib.phar
  rm install-pear-nozlib.phar

  # Link php from INSTALL_ROOT to system root.
  link_php

  # Configure pear.
  configure_pear
  echo "::endgroup::"
}
