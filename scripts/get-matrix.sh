#!/usr/bin/env bash

container_os_json_array=()
runner_os_json_array=()
sapi_json_array=()

# Store input container os versions in container_os_array,
# Store input runner os versions in runner_os_array,
# PHP SAPIs in sapi_array,
# and PHP versions to be built in php_array.
IFS=' ' read -r -a container_os_array <<<"${CONTAINER_OS_LIST:?}"
IFS=' ' read -r -a runner_os_array <<<"${RUNNER_OS_LIST:?}"
IFS=' ' read -r -a sapi_array <<<"${SAPI_LIST:?}"
IFS=' ' read -r -a php_array <<<"$(bash scripts/check-php-version.sh "${PHP_LIST:?}" "${COMMIT:-'--build-new'}")"

# Build a matrix array with container, distribution, distribution version and php-version and OS
for os in "${container_os_array[@]}"; do
 for php in "${php_array[@]}"; do
   container_os_json_array+=("{\"container\": \"$os\", \"php-version\": \"$php\", \"dist\": \"${os%:*}\", \"dist-version\": \"${os##*:}\", \"operating-system\": \"ubuntu-latest\"}")
 done
done

# Build a matrix array with runner os and php-version.
for os in "${runner_os_array[@]}"; do
  for php in "${php_array[@]}"; do
    runner_os_json_array+=("{\"os\": \"$os\", \"php-version\": \"$php\"}")
  done
done

# Build a matrix array with SAPI, container, distribution, distribution version and php-version and OS.
for os in "${container_os_array[@]}"; do
 for php in "${php_array[@]}"; do
   for sapi in "${sapi_array[@]}"; do
     sapi_json_array+=("{\"sapi\": \"$sapi\", \"container\": \"$os\", \"php-version\": \"$php\", \"dist\": \"${os%:*}\", \"dist-version\": \"${os##*:}\", \"php-version\": \"$php\", \"operating-system\": \"ubuntu-latest\"}")
   done
 done
done

# Output the matrices.
# shellcheck disable=SC2001
echo "::set-output name=container_os_matrix::{\"include\":[$(echo "${container_os_json_array[@]}" | sed -e 's|} {|}, {|g')]}"
# shellcheck disable=SC2001
echo "::set-output name=runner_os_matrix::{\"include\":[$(echo "${runner_os_json_array[@]}" | sed -e 's|} {|}, {|g')]}"
# shellcheck disable=SC2001
echo "::set-output name=sapi_matrix::{\"include\":[$(echo "${sapi_json_array[@]}" | sed -e 's|} {|}, {|g')]}"
