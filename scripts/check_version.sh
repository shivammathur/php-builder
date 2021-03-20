existing_version=$(curl -sL https://github.com/shivammathur/php-builder/releases/latest/download/php"$PHP_VERSION".log)
new_version=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($PHP_VERSION.[0-9]+)" | head -n 1)
if [ "$new_version" != "$existing_version" ] || [[ "$COMMIT" = *build-all* ]]; then
  echo "::set-output name=build::yes"
else
  echo "::set-output name=build::no"
fi