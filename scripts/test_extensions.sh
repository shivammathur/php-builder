set -e
php -m

extensions=()  
while read -r extension_config; do
  extensions+=($(echo "$extension_config" | cut -d ' ' -f 2 | cut -d '-' -f 1))
done < config/extensions/"$PHP_VERSION"

ext_dir="$(php-config --extension-dir)"

for extension in "${extensions[@]}"; do
  if grep -qx "$extension" config/optional-extensions; then
    test -f "$ext_dir/$extension.so"
    continue
  fi

  if [ "$extension" = "pcov" ]; then
    ln -sf /etc/php/"$PHP_VERSION"/mods-available/pcov.ini /etc/php/"$PHP_VERSION"/cli/conf.d/20-pcov.ini
  fi
  php -r "if(! extension_loaded(\"$extension\")) {throw new Exception(\"$extension not found\");}"
done
