# PHP Builder

<a href="https://github.com/shivammathur/php-builder" title="PHP Builder"><img alt="Build status" src="https://github.com/shivammathur/php-builder/workflows/Build%20PHP/badge.svg"></a>
<a href="https://github.com/shivammathur/php-builder/blob/main/LICENSE" title="license"><img alt="LICENSE" src="https://img.shields.io/badge/license-MIT-428f7e.svg"></a>
<a href="https://github.com/shivammathur/php-builder/tree/main/builds" title="builds"><img alt="PHP Versions Supported" src="https://img.shields.io/badge/php-8.0 and 8.1-8892BF.svg"></a>

- This projects builds PHP 8.0 and above (including a nightly build from the master branch of PHP) on `Ubuntu` and `Debian`.
- To install PHP, follow the instructions in the [install](#install) section.
- To download a PHP build, refer to the [builds](#Builds) section.

## Contents

- [OS Support](#os-support)
- [Install](#install)
- [SAPI Support](#sapi-support)
- [Builds](#builds)
- [Related Projects](#related-projects)
- [License](#license)
- [Dependencies](#dependencies)

## OS Support

- Ubuntu 16.04 (Xenial) and above.
- Debian 9 (Stretch) and above.

All other distributions based on the above operating systems will also be supported on best effort basis.

## Install

- Fetch the installer:

```bash
curl -sSLO https://github.com/shivammathur/php-builder/releases/latest/download/install.sh
chmod a+x ./install.sh
```

- Then, to install `PHP 8.0`:

```bash
./install.sh 8.0
```

or, to install `PHP 8.1.0-dev`:

```bash
./install.sh 8.1
```

- Finally, test your PHP version:

```bash
php -v
```

**Notes:**

- The requested PHP version would be installed at `/usr/local/php/<PHP VERSION>`.
- All the binaries for the PHP version would be linked in `/usr/bin`.
- The installer will switch to the PHP version you installed.

## SAPI support

These SAPIs are installed by default:

- apache2-handler
- cli
- cgi
- embed
- fpm
- phpdbg

These SAPI-server configurations can be set up with the `switch_sapi` script:

- `apache:apache` (apache2-handler with Apache)
- `fpm:apache` (php-fpm with Apache)
- `cgi:apache` (php-cgi with Apache)
- `fpm:nginx` (php-fpm with Nginx)

For example, to set up `php-fpm` with `Nginx`, run:

```bash
switch_sapi fpm:nginx
```

**Note:** When you run `switch_sapi`, the servers will have the default document root `/var/www/html`.

## Builds

### PHP 8.0

- [Ubuntu 16.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu16.04.tar.xz)
- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu20.04.tar.xz)
- [Ubuntu 21.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu21.04.tar.xz)
- [Debian 9](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bdebian9.tar.xz)
- [Debian 10](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bdebian10.tar.xz)
- [Debian 11](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bdebian11.tar.xz)

### PHP 8.1.0-dev (master)

- [Ubuntu 16.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu16.04.tar.xz)
- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu20.04.tar.xz)
- [Ubuntu 21.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu21.04.tar.xz)
- [Debian 9](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bdebian9.tar.xz)
- [Debian 10](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bdebian10.tar.xz)
- [Debian 11](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bdebian11.tar.xz)

## Related Projects
- [shivammathur/homebrew-php](https://github.com/shivammathur/homebrew-php)
- [shivammathur/php-builder-windows](https://github.com/shivammathur/php-builder-windows)
- [shivammathur/setup-php](https://github.com/shivammathur/setup-php)

## License

The scripts and documentation in this project are under the [MIT license](LICENSE). This project has multiple [dependencies](#dependencies). Their licenses can be found in their respective repositories.

## Dependencies

- [AMQP](https://github.com/php-amqp/php-amqp "AMQP PHP Extension")
- [APCU](https://github.com/krakjoe/apcu "APCU PHP Extension")
- [Deb.sury.org](https://github.com/oerdnj/deb.sury.org "PHP packaging for Ubuntu and Debian")
- [igbinary](https://github.com/igbinary/igbinary "Igbinary PHP Extension")
- [Imagick](https://github.com/Imagick/imagick "Imagick PHP Extension")
- [Memcache](https://github.com/websupport-sk/pecl-memcache "Memcache PHP Extension")
- [Memcached](https://github.com/php-memcached-dev/php-memcached "Memcached PHP Extension")
- [Msgpack](https://github.com/msgpack/msgpack-php "Msgpack PHP Extension")
- [Msphpsql](https://github.com/microsoft/msphpsql "Sqlsrv and pdo_sqlsrv extensions")
- [PEAR](https://github.com/pear/pear-core "PEAR PHP extension installer")
- [PCOV](https://github.com/krakjoe/pcov "PCOV PHP Extension")
- [PHP](https://github.com/php/php-src "PHP Upstream project")
- [php-build](https://github.com/php-build/php-build "php-build project")
- [PhpRedis](https://github.com/phpredis/phpredis "Redis PHP Extension")
- [Xdebug](https://github.com/xdebug/xdebug "Xdebug PHP Extension")
