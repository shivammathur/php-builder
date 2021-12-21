# PHP Builder

<a href="https://github.com/shivammathur/php-builder" title="PHP Builder"><img alt="Build status" src="https://github.com/shivammathur/php-builder/workflows/Build%20PHP/badge.svg"></a>
<a href="https://github.com/shivammathur/php-builder/blob/main/LICENSE" title="license"><img alt="LICENSE" src="https://img.shields.io/badge/license-MIT-428f7e.svg"></a>
<a href="https://github.com/shivammathur/php-builder/tree/main/builds" title="builds"><img alt="PHP Versions Supported" src="https://img.shields.io/badge/php-8.0 to 8.2-8892BF.svg"></a>

- This projects builds PHP 8.0 and above (including a nightly build from the master branch of PHP) on `Ubuntu` and `Debian`.
- To install PHP, follow the instructions in the [install](#install) section.
- To download a PHP build, refer to the [builds](#Builds) section.

## Contents

- [OS Support](#os-support)
- [Install](#install)
- [Extensions](#extensions)
- [JIT](#jit)
- [SAPI Support](#sapi-support)
- [Builds](#builds)
- [Uninstall](#uninstall)
- [Related Projects](#related-projects)
- [License](#license)
- [Dependencies](#dependencies)

## OS Support

- Ubuntu 18.04 (Bionic) amd64
- Ubuntu 20.04 (Focal) amd64
- Ubuntu 21.04 (Hirsute) amd64
- Debian 9 (Stretch) amd64
- Debian 10 (Buster) amd64
- Debian 11 (Bullseye) amd64

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

or, to install `PHP 8.1`:

```bash
./install.sh 8.1
```

- Finally, test your PHP version:

```bash
php -v
```

**Notes:**

- All PHP versions have prefix `/usr` and the directory structure will be same as that of Debian builds.
- Any pre-existing extensions INI configuration for the PHP version will be removed upon installation.
- The installer will switch to the PHP version you installed.

## Extensions

<ul><li><details>
  <summary>Expand to check the extensions installed along with PHP.</summary>
  <br>

`amqp`, `apcu`, `ast`, `bcmath`, `bz2`, `calendar`, `Core`, `ctype`, `curl`, `date`, `dba`, `dom`, `ds`, `enchant`, `exif`, `FFI`, `fileinfo`, `filter`, `ftp`, `gd`, `gettext`, `gmp`, `hash`, `iconv`, `igbinary`, `imagick`, `imap`, `intl`, `json`, `ldap`, `libxml`, `mbstring`, `memcache`, `memcached`, `mongodb`, `msgpack`, `mysqli`, `mysqlnd`, `odbc`, `openssl`, `pcntl`, `pcov`, `pcre`, `PDO`, `pdo_dblib`, `PDO_Firebird`, `pdo_mysql`, `PDO_ODBC`, `pdo_pgsql`, `pdo_sqlite`, `pdo_sqlsrv`, `pgsql`, `Phar`, `posix`, `pspell`, `readline`, `redis`, `Reflection`, `session`, `shmop`, `SimpleXML`, `soap`, `sockets`, `sodium`, `SPL`, `sqlite3`, `sqlsrv`, `standard`, `sysvmsg`, `sysvsem`, `sysvshm`, `tidy`, `tokenizer`, `xdebug`, `xml`, `xmlreader`, `xmlwriter`, `xsl`, `zip`, `zlib`, `Xdebug`, `Zend OPcache`

</details></li></ul>

- Extension PCOV is disabled by default as Xdebug is enabled.

- You can switch to PCOV by disabling Xdebug using `phpdismod` and enabling it using `phpenmod`.

```bash
phpdismod -v <ALL|php-version> -s <ALL|sapi-name> xdebug
phpenmod -v <ALL|php-version> -s <ALL|sapi-name> pcov
```

- More extensions can also be installed from [`ppa:ondrej/php`](https://launchpad.net/~ondrej/+archive/ubuntu/php)

- `PECL` is also installed along with PHP, so compatible extensions can also be installed using it. These will be enabled using the `pecl.ini` module which is linked to all SAPIs.

```bash
pecl install <extension>
```

## JIT

PHP 8.0 and above versions have a JIT(Just-In-Time) compiler.

It is disabled by default, and can be enabled by the following steps:

- First, disable Xdebug and PCOV as they are not compatible with JIT.

```bash
phpdismod -v <ALL|php-version> -s <ALL|sapi-name> xdebug pcov
```

- Then enable JIT using the `switch_jit` script for the same PHP versions and SAPIs.

```bash
switch_jit -v <ALL|php-version> -s <ALL|sapi-name> enable -m <jit_mode> -b <jit_buffer_size>
```

If you do not specify `-m` or `-b`, the default for JIT mode is `tracing`, and for JIT buffer size it is `128M`.

- If you get a warning about incompatible extensions, check if you installed any other third-party extensions which are incompatible with JIT.

To disable JIT:

```bash
switch_jit -v <php-version> -s <ALL|sapi-name> disable
```

## SAPI support

These SAPIs are installed by default:

- `apache2-handler`
- `cli`
- `cgi`
- `embed`
- `fpm`
- `phpdbg`

These SAPI:server configurations can be set up with the `switch_sapi` script:

- `apache:apache` (apache2-handler with Apache)
- `fpm:apache` (php-fpm with Apache)
- `cgi:apache` (php-cgi with Apache)
- `fpm:nginx` (php-fpm with Nginx)

```bash
switch_sapi -v <php-version> -s <sapi|sapi:server>
```

**Note:** When you run `switch_sapi`, the servers will have the default document root `/var/www/html`.

## Builds

### PHP 8.0

- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu20.04.tar.xz)
- [Ubuntu 21.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bubuntu21.04.tar.xz)
- [Debian 9](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bdebian9.tar.xz)
- [Debian 10](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bdebian10.tar.xz)
- [Debian 11](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.0%2Bdebian11.tar.xz)

### PHP 8.1.0-dev

- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu20.04.tar.xz)
- [Ubuntu 21.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bubuntu21.04.tar.xz)
- [Debian 9](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bdebian9.tar.xz)
- [Debian 10](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bdebian10.tar.xz)
- [Debian 11](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.1%2Bdebian11.tar.xz)

### PHP 8.2.0-dev (master)

- [Ubuntu 18.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.2%2Bubuntu18.04.tar.xz)
- [Ubuntu 20.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.2%2Bubuntu20.04.tar.xz)
- [Ubuntu 21.04](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.2%2Bubuntu21.04.tar.xz)
- [Debian 9](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.2%2Bdebian9.tar.xz)
- [Debian 10](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.2%2Bdebian10.tar.xz)
- [Debian 11](https://github.com/shivammathur/php-builder/releases/latest/download/php_8.2%2Bdebian11.tar.xz)

## Uninstall

- Fetch the installer:

```bash
curl -sSLO https://github.com/shivammathur/php-builder/releases/latest/download/install.sh
chmod a+x ./install.sh
```

- Then, to remove `PHP 8.0`:

```bash
./install.sh --remove 8.0
```

or, to remove `PHP 8.1`:

```bash
./install.sh --remove 8.1
```

## Related Projects
- [shivammathur/homebrew-php](https://github.com/shivammathur/homebrew-php)
- [shivammathur/php-builder-windows](https://github.com/shivammathur/php-builder-windows)
- [shivammathur/setup-php](https://github.com/shivammathur/setup-php)

## License

The scripts and documentation in this project are under the [MIT license](LICENSE). This project has multiple [dependencies](#dependencies). Their licenses can be found in their respective repositories.

## Dependencies

- [AMQP](https://github.com/php-amqp/php-amqp "AMQP PHP Extension")
- [APCU](https://github.com/krakjoe/apcu "APCU PHP Extension")
- [AST](https://github.com/nikic/php-ast "AST PHP Extension")
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
