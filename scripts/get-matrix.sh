json_array=()
IFS=' ' read -r -a os_arr <<<"$OS_VERSIONS"
IFS=' ' read -r -a php_arr <<<"$(bash scripts/check-php-version.sh "$PHP_VERSIONS" "$COMMIT")"
for os in "${os_arr[@]}"; do
 for php in "${php_arr[@]}"; do
   json_array+=("{\"operating-system\": \"ubuntu-latest\", \"container\": \"$os\", \"dist\": \"${os%:*}\", \"php-version\": \"$php\"}")
 done
done
# shellcheck disable=SC2001
echo "::set-output name=matrix::{\"include\":[$(echo "${json_array[@]}" | sed -e 's|} {|}, {|g')]}"