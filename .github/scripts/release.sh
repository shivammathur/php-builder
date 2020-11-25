set -x
curl -o ./install.sh -sL https://dl.bintray.com/shivammathur/php/php-builder.sh
assets=()
for asset in ./builds/*/*; do
  assets+=("$asset")
done
assets+=("./install.sh")
for version in 8.0 8.1; do
  tag=$(curl -sL https://api.github.com/repos/php/php-src/tags | grep -Po "php-$version.[0-9]+" | tail -n 1)
  if [ "$tag" = "" ]; then tag='nightly'; fi
  echo "$tag" > "php$version.log"
  assets+=("./php$version.log")
done
gh release delete "builds" -y || true
gh release create "builds" "${assets[@]}" -t "builds" -n "builds"
