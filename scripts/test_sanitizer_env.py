#!/usr/bin/env python3
# Run on Linux with sudo and PyYAML: python3 scripts/test_sanitizer_env.py
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import yaml

repo = Path(__file__).resolve().parent.parent
env = dict(os.environ)
for name in ('USE_ZEND_ALLOC', 'ASAN_OPTIONS', 'UBSAN_OPTIONS', 'ZEND_DONT_UNLOAD_MODULES', 'LD_PRELOAD'):
    env.pop(name, None)

# Check real sudo behavior for unset and explicitly supplied variables.
for script in ('install.sh', 'test_pecl.sh', 'test_sapi.sh'):
    source = (repo / 'scripts' / script).read_text()
    start = source.index('sudo_php_env() {')
    helper = source[start:source.index('\n}', start) + 2]
    for value in (None, '0', '1', ''):
        test_env = dict(env)
        if value is not None:
            test_env['USE_ZEND_ALLOC'] = value
        command = helper + '\nsudo_php_env bash -c \'printf "%s\\n%s" "${USE_ZEND_ALLOC-unset}" "${ZEND_DONT_UNLOAD_MODULES-unset}"\''
        actual = subprocess.check_output(['bash', '-c', command], env=test_env, text=True)
        assert actual == ('unset' if value is None else value) + '\nunset', (script, value, actual)

# Run the service-config helpers only, redirecting all /etc writes into a temp directory.
source = (repo / 'scripts/test_sapi.sh').read_text()
source = source[:source.index('\nsudo mkdir -p /var/www/html')]
with tempfile.TemporaryDirectory() as tmp:
    etc = Path(tmp, 'etc')
    (etc / 'default').mkdir(parents=True)
    command = source.replace('/etc/', f'{etc}/') + '''
sudo() {
  case "$1" in systemctl) return 0 ;; --preserve-env=*) shift ;; esac
  "$@"
}
configure_asan_env || exit $?
test -z "${LD_PRELOAD+x}" || exit 1
sudo_php_env bash -c 'test -z "${LD_PRELOAD+x}"'
'''
    fpm_env = dict(env, PHP_VERSION='8.4')
    assert subprocess.run(['bash', '-c', command], env=fpm_env).returncode == 1
    service = etc / 'systemd/system/php8.4-fpm.service.d/asan-env.conf'
    assert not service.exists(), 'Regular tests must not configure ASAN services'
    fpm_env.update(ASAN_OPTIONS='detect_leaks=0', ZEND_DONT_UNLOAD_MODULES='1')
    for value in (None, '0', '1'):
        test_env = dict(fpm_env)
        if value is not None:
            test_env['USE_ZEND_ALLOC'] = value
        subprocess.run(['bash', '-c', command], env=test_env, check=True)
        expected = '1' if value is None else value
        assert (etc / 'default/php-fpm8.4').read_text().splitlines().count(f'export USE_ZEND_ALLOC={expected}') == 1
        assert service.read_text().splitlines().count(f'Environment="USE_ZEND_ALLOC={expected}"') == 1
        assert 'LD_PRELOAD' not in service.read_text()
    assert not (etc / 'apache2').exists(), 'SAPI tests must use the packaged Apache configuration'

# Exercise packaging and switching without touching the host's services or /etc.
source = (repo / 'scripts/build.sh').read_text()
start = source.index('merge_sapi() {')
merge = source[start:source.index('\n}', start) + 2]
switch = (repo / 'scripts/switch_sapi').read_text()
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp, 'root')
    cli = Path(tmp, 'root-cli')
    for filename in ('usr/bin/php8.4', 'usr/bin/phar8.4.phar', 'usr/share/man/man1/phar8.4.phar.1'):
        path = cli / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
    Path(tmp, 'config').mkdir()
    for path in (repo / 'config').glob('*'):
        if path.name == 'default_nginx' or path.name.startswith('apache2-asan.'):
            shutil.copy(path, Path(tmp, 'config', path.name))
    Path(tmp, 'scripts').symlink_to(repo / 'scripts')
    asan_lib = Path(tmp, 'libasan.so')
    asan_lib.touch()
    test_env = dict(env, INSTALL_ROOT=str(root), PHP_VERSION='8.4', SAPI_LIST='cli', TEST_ASAN_LIB=str(asan_lib))
    command = merge + '''
link_php() { :; }
switch_version() { :; }
ldd() { printf 'libasan.so.8 => %s (0x0)\\n' "$TEST_ASAN_LIB"; }
merge_sapi
'''
    packaged_env = root / 'etc/php/8.4/apache2/asan-envvars'
    for asan in ('', 'asan'):
        test_env['ASAN'] = asan
        subprocess.run(['bash', '-ec', command], cwd=tmp, env=test_env, check=True)
        assert packaged_env.exists() == (asan == 'asan'), 'Apache ASAN environment must ship only in ASAN builds'
    assert str(asan_lib) in packaged_env.read_text()
    assert 'ASAN_LIB' not in packaged_env.read_text()
    missing_lib = subprocess.run(['bash', '-ec', command], cwd=tmp, env=dict(test_env, TEST_ASAN_LIB='/missing/libasan.so'), capture_output=True, text=True)
    assert missing_lib.returncode == 1 and 'Cannot find the ASAN runtime' in missing_lib.stderr
    conf = root / 'etc/apache2/conf-available/php-asan-env.conf'
    assert set(conf.read_text().splitlines()) == {
        f'PassEnv {name}' for name in ('ASAN_OPTIONS', 'UBSAN_OPTIONS', 'ZEND_DONT_UNLOAD_MODULES', 'USE_ZEND_ALLOC', 'LD_PRELOAD')
    }

    apache = root / 'etc/apache2'
    (apache / 'conf-enabled').mkdir()
    (apache / 'envvars').write_text('export APACHE_TEST_VALUE=kept\n')
    (root / 'etc/init.d').mkdir()
    (root / 'etc/init.d/apache2').touch()
    mocks = '''
check_installed() { return 0; }
apache2() { echo 'Apache/2.4.0'; }
install_php_sapi() { :; }
a2enmod() { :; }
a2dismod() { :; }
a2enconf() { ln -sf "/etc/apache2/conf-available/$1.conf" "/etc/apache2/conf-enabled/$1.conf"; }
a2disconf() { rm -f "/etc/apache2/conf-enabled/$1.conf"; }
service() { test -z "${LD_PRELOAD+x}" || exit 1; }
debconf-set-selections() { :; }
'''
    command = switch.replace("\napt_mgr='apt-get'", mocks + "\napt_mgr='apt-get'").replace('/etc/', f'{root}/etc/')
    clean_env = dict(env)
    for sapi in ('apache2handler:apache', 'apache2handler:apache', 'fpm:apache', 'cgi:apache', 'apache'):
        subprocess.run(['bash', '-c', command, '--', '-v', '8.4', '-s', sapi], env=clean_env, check=True)
        assert (apache / 'conf-enabled/php-asan-env.conf').exists(), sapi
        values = subprocess.check_output(['bash', '-c', f'''
. "{apache}/envvars"
printf '%s\\n' "$ASAN_OPTIONS" "$UBSAN_OPTIONS" "$ZEND_DONT_UNLOAD_MODULES" "$USE_ZEND_ALLOC" "$LD_PRELOAD" "$APACHE_TEST_VALUE"
'''], env=clean_env, text=True).splitlines()
        assert values == ['detect_leaks=0', 'halt_on_error=1', '1', '0', str(asan_lib), 'kept'], (sapi, values)
    assert (apache / 'envvars').read_text().count(' || . ') == 1, 'Repeated switches must not duplicate the source line'

    for value in ('0', '1', ''):
        actual = subprocess.check_output(['bash', '-c', f'. "{apache}/envvars"; printf "%s" "$USE_ZEND_ALLOC"'], env=dict(clean_env, USE_ZEND_ALLOC=value), text=True)
        assert actual == value, 'Apache must preserve explicit allocator settings'

    # Switching to another regular PHP version must disable the ASAN environment.
    subprocess.run(['bash', '-c', command, '--', '-v', '8.3', '-s', 'apache2handler:apache'], env=clean_env, check=True)
    assert not (apache / 'conf-enabled/php-asan-env.conf').exists()
    subprocess.run(['bash', '-c', command, '--', '-v', '8.4', '-s', 'apache2handler:apache'], env=clean_env, check=True)

    # The installer removes /etc/php/<version> when replacing an ASAN build.
    packaged_env.unlink()
    subprocess.run(['bash', '-c', command, '--', '-v', '8.4', '-s', 'apache2handler:apache'], env=clean_env, check=True)
    assert not (apache / 'conf-enabled/php-asan-env.conf').exists()
    subprocess.run(['bash', '-c', f'. "{apache}/envvars"; test -z "${{LD_PRELOAD+x}}"'], env=clean_env, check=True)

for filename in ('build.yml', 'package.yml', 'package-extensions.yml'):
    source = (repo / '.github/workflows' / filename).read_text()
    assert 'detect_odr_violation=0' not in source, filename
    assert 'report_globals=0' not in source, filename
    workflow = yaml.safe_load(source)
    for job in ('package', 'local-test', 'github-test'):
        runtime = next(step for step in workflow['jobs'][job]['steps'] if step.get('name') == 'Configure ASAN runtime')
        assert runtime['if'] == "matrix.asan == 'asan'", (filename, job)
        assert 'echo "USE_ZEND_ALLOC=0" >> "$GITHUB_ENV"' in runtime['run'], (filename, job)

print('Sanitizer environment checks passed: sudo, FPM, Apache, and all three workflows.')
