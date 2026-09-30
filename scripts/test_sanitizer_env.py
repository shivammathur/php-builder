#!/usr/bin/env python3
# Run on Linux with PyYAML: python3 scripts/test_sanitizer_env.py
import os
from pathlib import Path
import subprocess
import tempfile

import yaml

repo = Path(__file__).resolve().parent.parent
env = dict(os.environ)
for name in ('USE_ZEND_ALLOC', 'ASAN_OPTIONS', 'UBSAN_OPTIONS', 'ZEND_DONT_UNLOAD_MODULES', 'LD_PRELOAD'):
    env.pop(name, None)

# Simulate sudo dropping the caller's allocator setting.
sudo = 'sudo() { env -u USE_ZEND_ALLOC "$@"; }\n'
for script in ('install.sh', 'test_pecl.sh', 'test_sapi.sh'):
    source = (repo / 'scripts' / script).read_text()
    start = source.index('sudo_php_env() {')
    helper = source[start:source.index('\n}', start) + 2]
    for value in (None, '0', '1', ''):
        test_env = dict(env)
        if value is not None:
            test_env['USE_ZEND_ALLOC'] = value
        command = sudo + helper + '\nsudo_php_env bash -c \'printf "%s" "${USE_ZEND_ALLOC-unset}"\''
        actual = subprocess.check_output(['bash', '-c', command], env=test_env, text=True)
        assert actual == ('1' if value is None else value), (script, value, actual)

# Run the service-config helpers only, redirecting all /etc writes into a temp directory.
source = (repo / 'scripts/test_sapi.sh').read_text()
source = source[:source.index('\nsudo mkdir -p /var/www/html')]
with tempfile.TemporaryDirectory() as tmp:
    etc = Path(tmp, 'etc')
    (etc / 'default').mkdir(parents=True)
    (etc / 'apache2/conf-available').mkdir(parents=True)
    (etc / 'apache2/envvars').touch()
    command = source.replace('/etc/', f'{etc}/') + '''
set_asan_lib() { :; }
sudo() {
  case "$1" in systemctl|a2enconf) return 0 ;; esac
  env -u USE_ZEND_ALLOC "$@"
}
configure_asan_env
'''
    env.update(PHP_VERSION='8.4')
    assert subprocess.run(['bash', '-c', command], env=env).returncode == 1
    service = etc / 'systemd/system/php8.4-fpm.service.d/asan-env.conf'
    assert not service.exists(), 'Regular tests must not configure ASAN services'
    env.update(ASAN_OPTIONS='detect_leaks=0', ZEND_DONT_UNLOAD_MODULES='1')
    for value in (None, '0', '1'):
        test_env = dict(env)
        if value is not None:
            test_env['USE_ZEND_ALLOC'] = value
        subprocess.run(['bash', '-c', command], env=test_env, check=True)
        expected = '1' if value is None else value
        for path in (etc / 'default/php-fpm8.4', etc / 'apache2/envvars'):
            assert path.read_text().splitlines().count(f'export USE_ZEND_ALLOC={expected}') == 1, path
        assert service.read_text().splitlines().count(f'Environment="USE_ZEND_ALLOC={expected}"') == 1
        assert 'PassEnv USE_ZEND_ALLOC' in (etc / 'apache2/conf-available/php-asan-env.conf').read_text().splitlines()

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
