# PHP Builder

<a href="https://github.com/shivammathur/php-builder" title="PHP Builder"><img alt="Build status" src="https://github.com/shivammathur/php-builder/workflows/Build%20PHP/badge.svg"></a>
<a href="https://github.com/shivammathur/php-builder/blob/master/LICENSE" title="license"><img alt="LICENSE" src="https://img.shields.io/badge/license-MIT-428f7e.svg"></a>
<a href="https://github.com/shivammathur/php-builder/tree/master/builds" title="builds"><img alt="PHP Versions Supported" src="https://img.shields.io/badge/php-8.0 and 8.1-8892BF.svg"></a>

> Build PHP nightly using GitHub Actions for Ubuntu.

- This projects builds PHP nightly for [setup-php](https://github.com/shivammathur/php-builder) on `Ubuntu`.
- To install a build follow the instructions in the [install](#Install) section. To download a build refer to the [builds](#Builds) section.
- If you want to build PHP for any other linux distribution, you may refer to the build scripts in the `.github` directory.  

## Install

- Make sure sudo and curl are installed.
```bash
apt-get update
apt-get install -y curl sudo
```

- Fetch the script
```bash
curl -sSLO https://github.com/shivammathur/php-builder/releases/latest/download/install.sh
chmod a+x ./install.sh
```

-  Install PHP 8.0
```bash
./install.sh local 8.0
```

or

- Install PHP 8.1.0-dev
```bash
./install.sh local 8.1 
```

- Test PHP
```bash
php -v
```

- **Note:** PHP builds are installed at `/usr/local/php/`.

## Builds

### PHP 8.0

- [Ubuntu 16.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu16.04.tar.xz)
- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu20.04.tar.xz)

### PHP 8.1.0-dev (master)

- [Ubuntu 16.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu16.04.tar.xz)
- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu20.04.tar.xz)


## Related Projects
- [shivammathur/homebrew-php](https://github.com/shivammathur/homebrew-php)
- [shivammathur/php-builder-windows](https://github.com/shivammathur/php-builder-windows)
- [shivammathur/setup-php](https://github.com/shivammathur/setup-php)

## License

The code in this project is licensed under the [MIT license](LICENSE). This project has multiple [dependencies](#dependencies). Their licenses can be found in their respective repositories.

## Dependencies

- [Imagick](https://github.com/Imagick/imagick "Imagick PHP Extension")
- [PEAR](https://github.com/pear/pear-core "PEAR PHP extension installer")
- [PCOV](https://github.com/krakjoe/pcov "PCOV PHP Extension")
- [PHP](https://github.com/php/php-src "PHP Upstream project")
- [php-build](https://github.com/php-build/php-build "php-build")
- [Xdebug](https://github.com/xdebug/xdebug "Xdebug PHP Extension")
# PHP Builder

<a href="https://github.com/shivammathur/php-builder" title="PHP Builder"><img alt="Build status" src="https://github.com/shivammathur/php-builder/workflows/Build%20PHP/badge.svg"></a>
<a href="https://github.com/shivammathur/php-builder/blob/master/LICENSE" title="license"><img alt="LICENSE" src="https://img.shields.io/badge/license-MIT-428f7e.svg"></a>
<a href="https://github.com/shivammathur/php-builder/tree/master/builds" title="builds"><img alt="PHP Versions Supported" src="https://img.shields.io/badge/php-8.0 and 8.1-8892BF.svg"></a>

> Build PHP nightly using GitHub Actions for Ubuntu.

- This projects builds PHP nightly for [setup-php](https://github.com/shivammathur/php-builder) on `Ubuntu`.
- To install a build follow the instructions in the [install](#Install) section. To download a build refer to the [builds](#Builds) section.
- If you want to build PHP for any other linux distribution, you may refer to the build scripts in the `.github` directory.  

## Install

- Make sure sudo and curl are installed.
```bash
apt-get update
apt-get install -y curl sudo
```

- Fetch the script
```bash
curl -sSLO https://github.com/shivammathur/php-builder/releases/latest/download/install.sh
chmod a+x ./install.sh
```

-  Install PHP 8.0
```bash
./install.sh local 8.0
```

or

- Install PHP 8.1.0-dev
```bash
./install.sh local 8.1 
```

- Test PHP
```bash
php -v
```

- **Note:** PHP builds are installed at `/usr/local/php/`.

## Builds

### PHP 8.0

- [Ubuntu 16.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu16.04.tar.xz)
- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu20.04.tar.xz)

### PHP 8.1.0-dev (master)

- [Ubuntu 16.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu16.04.tar.xz)
- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu20.04.tar.xz)


## Related Projects
- [shivammathur/homebrew-php](https://github.com/shivammathur/homebrew-php)
- [shivammathur/php-builder-windows](https://github.com/shivammathur/php-builder-windows)
- [shivammathur/setup-php](https://github.com/shivammathur/setup-php)

## License

The code in this project is licensed under the [MIT license](LICENSE). This project has multiple [dependencies](#dependencies). Their licenses can be found in their respective repositories.

## Dependencies

- [deb.sury.org](https://github.com/oerdnj/deb.sury.org)
- [Imagick](https://github.com/Imagick/imagick "Imagick PHP Extension")
- [PEAR](https://github.com/pear/pear-core "PEAR PHP extension installer")
- [PCOV](https://github.com/krakjoe/pcov "PCOV PHP Extension")
- [PHP](https://github.com/php/php-src "PHP Upstream project")
- [php-build](https://github.com/php-build/php-build "php-build")
- [Xdebug](https://github.com/xdebug/xdebug "Xdebug PHP Extension")
