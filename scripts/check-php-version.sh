IFS=' ' read -r -a php_versions_to_check <<<"$1"
php_versions_to_build=()
if [[ "$2" = *build-all* ]]; then
  php_versions_to_build=("${php_versions_to_check[@]}")
else
  for php_version in "${php_versions_to_check[@]}"; do
    existing_version=$(curl -sL https://github.com/shivammathur/php-builder/releases/latest/download/php"$php_version".log)
    new_version=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($php_version.[0-9]+)" | head -n 1)
    if [ "$new_version" != "$existing_version" ]; then
      php_versions_to_build+=("$php_version")
    fi
  done
fi
echo "${php_versions_to_build[@]}"