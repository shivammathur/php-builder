# PHP Builder

<a href="https://github.com/shivammathur/php-builder" title="PHP Builder"><img alt="Build status" src="https://github.com/shivammathur/php-builder/workflows/Build%20PHP/badge.svg"></a>
<a href="https://github.com/shivammathur/php-builder/blob/master/LICENSE" title="license"><img alt="LICENSE" src="https://img.shields.io/badge/license-MIT-428f7e.svg"></a>
<a href="https://github.com/shivammathur/php-builder/tree/master/builds" title="builds"><img alt="PHP Versions Supported" src="https://img.shields.io/badge/php-%3E%3D%208.0.0-8892BF.svg"></a>

> Build PHP nightly using GitHub Actions for Ubuntu.


## Builds

- [Ubuntu 16.04](https://bintray.com/shivammathur/php/download_file?file_path=php_8.0%2Bubuntu16.04.tar.xz)
- [Ubuntu 18.04](https://bintray.com/shivammathur/php/download_file?file_path=php_8.0%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://bintray.com/shivammathur/php/download_file?file_path=php_8.0%2Bubuntu20.04.tar.xz)


## Install

- Make sure sudo and curl are installed.
```bash
apt-get update
apt-get install -y curl sudo
```

- Fetch the script and install.
```bash
curl -sSLO https://github.com/shivammathur/php-builder/releases/latest/download/install.sh
chmod a+x ./install.sh
./install.sh
```

- Test PHP
```bash
php -v
```


## License

The code in this project is licensed under the [MIT license](LICENSE). This project has multiple [dependencies](#dependencies). Their licenses can be found in their respective repositories.


## Dependencies

- [PEAR](https://github.com/pear/pear-core "PEAR PHP extension installer")
- [PCOV](https://github.com/krakjoe/pcov "PCOV PHP Extension")
- [PHP](https://github.com/php/php-src "PHP Upstream project")
- [php-build](https://github.com/php-build/php-build "php-build")
- [Xdebug](https://github.com/xdebug/xdebug "Xdebug PHP Extension")