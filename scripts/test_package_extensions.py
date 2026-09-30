#!/usr/bin/env python3
# Run on Linux with PyYAML: python3 scripts/test_package_extensions.py
import json
import os
from pathlib import Path
import subprocess
import tempfile

import yaml

repo = Path(__file__).resolve().parent.parent
workflow = yaml.safe_load((repo / '.github/workflows/package-extensions.yml').read_text())
jobs = workflow['jobs']
steps = {step['name']: step for step in jobs['package']['steps']}
for name in ('Download source release packages', 'Stage and install source package',
             'Rebuild extensions and package', 'Check packaged extensions and debug symbols'):
    assert steps[name]['env'].get('ASAN') == '${{ matrix.asan }}', name

artifact = steps['Upload artifact']['with']['name']
for job, runner in (('local-test', 'local'), ('github-test', 'github')):
    download = next(step for step in jobs[job]['steps'] if 'download-artifact@' in step.get('uses', ''))
    name = download['with']['name'].replace('${{ matrix.os }}', '${{ matrix.dist }}-${{ matrix.dist-version }}')
    assert name == artifact, job
    install = next(step for step in jobs[job]['steps'] if step.get('name') == 'Install PHP')
    assert f'{runner} ${{{{ matrix.debug }}}} ${{{{ matrix.build }}}} ${{{{ matrix.asan }}}}' in install['run'], job

for job in ('package', 'local-test', 'github-test'):
    runtime = next(step for step in jobs[job]['steps'] if step.get('name') == 'Configure ASAN runtime')
    assert runtime['if'] == "matrix.asan == 'asan'", job
    assert 'ASAN_OPTIONS=' in runtime['run'] and 'ZEND_DONT_UNLOAD_MODULES=1' in runtime['run'], job

# Only execute archive selection, never downloads or installation into /.
stage = (repo / 'scripts/stage-package-extensions.sh').read_text()
stage = stage[:stage.index('mkdir -p "$install_root"')]
download = steps['Download source release packages']['run']
download = download[:download.index('mkdir -p /tmp/source-artifact')]
check = steps['Check packaged extensions and debug symbols']['run']
check = check[:check.index('mapfile -t packages')]

with tempfile.TemporaryDirectory() as tmp:
    env = dict(os.environ, **workflow['env'], PHP_LIST='8.7', COMMIT='--build-all',
               PHP_SOURCE='--web-php', GITHUB_OUTPUT=f'{tmp}/matrix')
    subprocess.run(['bash', 'scripts/get-matrix.sh'], cwd=repo, env=env, check=True)
    outputs = dict(line.split('=', 1) for line in Path(env['GITHUB_OUTPUT']).read_text().splitlines())
    rows = json.loads(outputs['container_os_matrix'])['include']
    assert {(row['build'], row['asan']) for row in rows} == {('nts', ''), ('zts', ''), ('nts', 'asan'), ('zts', 'asan')}
    names = []
    for row in rows:
        name = artifact.replace("${{ matrix.asan && '-asan' || '' }}", '-asan' if row['asan'] else '')
        for key, value in row.items():
            name = name.replace('${{ matrix.' + key + ' }}', value)
        assert '${{' not in name, name
        names.append(name)
    assert len(names) == len(set(names)), 'Duplicate artifact names'

    for suffix in ('', '-zts', '-asan', '-zts-asan'):
        for debug in ('', '-dbgsym'):
            Path(tmp, f'php_8.7{suffix}{debug}+ubuntu24.04.tar.zst').touch()
    for build, asan, suffix in (('nts', '', ''), ('zts', '', '-zts'),
                                ('nts', 'asan', '-asan'), ('zts', 'asan', '-zts-asan')):
        env.update(BUILD=build, ASAN=asan, PHP_VERSION='8.7', EXTENSIONS_TO_BUILD='psr', SOURCE_ARTIFACT_DIR=tmp)
        result = subprocess.check_output(['bash', '-ec', stage + '\nprintf "%s\\n" "${package_archives[0]}" "${debug_archives[0]}"'], env=env, text=True)
        assert result.splitlines() == [f'{tmp}/php_8.7{suffix}{debug}+ubuntu24.04.tar.zst' for debug in ('', '-dbgsym')]
        result = subprocess.check_output(['bash', '-ec', download + '\nprintf "%s\\n" "$package" "$debug_package"'], env=env, text=True)
        package, debug_package = result.splitlines()
        assert package.startswith(f'php_8.7{suffix}+') and debug_package.startswith(f'php_8.7{suffix}-dbgsym+')
        result = subprocess.check_output(['bash', '-ec', check + '\nprintf "%s" "$suffix"'], env=env, text=True)
        assert result == suffix, (build, asan, result)

print('Extension package checks passed: four variants, distinct artifacts, matching archives and test jobs.')
