"""Publish the approved October 24 builds without compiling or repackaging them."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

REPO = 'shivammathur/php-builder'
ROOT = Path(__file__).resolve().parent
RECEIPTS = Path('receipts')


def gh(*args):
    for attempt in range(4):
        result = subprocess.run(['gh', *args], capture_output=True)
        if result.returncode == 0:
            return result.stdout
        if attempt == 3:
            raise RuntimeError(result.stderr.decode(errors='replace'))
        time.sleep(3 * (attempt + 1))


def api(path):
    return json.loads(gh('api', f'repos/{REPO}/{path}'))


def save(name, data):
    RECEIPTS.mkdir(exist_ok=True)
    target = RECEIPTS / name
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(target)


def digest(path):
    with path.open('rb') as stream:
        return 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def download_artifact(artifact, target):
    token = os.environ.get('GH_TOKEN') or gh('auth', 'token').decode().strip()
    request = urllib.request.Request(
        f'https://api.github.com/repos/{REPO}/actions/artifacts/{artifact["id"]}/zip',
        headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json'},
    )
    try:
        urllib.request.build_opener(NoRedirect).open(request, timeout=60)
        raise RuntimeError('Expected artifact download redirect')
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise
        url = error.headers['Location']
    # The signed storage request deliberately carries no GitHub credentials.
    subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location',
                    '--retry', '5', '--output', str(target), url], check=True)
    assert target.stat().st_size == artifact['size_in_bytes'], artifact['name']
    assert digest(target) == artifact['digest'], artifact['name']


def release_assets(version):
    release = api('releases/tags/' + version)
    return release, {item['name']: item for item in release['assets']}


def upload(version, files, source):
    expected = {path.name: {'digest': digest(path), 'size': path.stat().st_size}
                for path in files}
    _, current = release_assets(version)
    changed = [path for path in files
               if path.name not in current
               or any(current[path.name].get(key) != value
                      for key, value in expected[path.name].items())]
    if changed:
        gh('release', 'upload', version, '--repo', REPO, '--clobber', *map(str, changed))
    _, current = release_assets(version)
    receipts = []
    for name, metadata in expected.items():
        asset = current[name]
        assert asset['state'] == 'uploaded', name
        assert all(asset.get(key) == value for key, value in metadata.items()), name
        receipts.append({'name': name, **metadata, 'asset_id': asset['id'],
                         'url': asset['browser_download_url'], 'source': source})
    return receipts


def preflight(version, config):
    assert os.environ.get('GITHUB_REPOSITORY', REPO) == REPO
    assert config['php'] == version
    assert digest(Path('scripts/install.sh')) == config['installer_digest']
    run = api(f'actions/runs/{config["run"]}')
    assert run['head_sha'] == config['head'] and run['conclusion'] == 'success'
    assert run['status'] == 'completed'
    assert run['head_repository']['full_name'] == REPO
    actual = []
    for page in range(1, 20):
        response = api(f'actions/runs/{config["run"]}/artifacts?per_page=100&page={page}')
        actual.extend(response['artifacts'])
        if len(actual) >= response['total_count']:
            break
    selected = {item['id']: item for item in actual
                if item['name'].startswith(f'php{version}-')}
    assert len(selected) == len(config['artifacts']) == 16
    names = set()
    for expected in config['artifacts']:
        artifact = selected[expected['id']]
        assert not artifact['expired']
        assert artifact['workflow_run']['head_sha'] == config['head']
        for key in ('name', 'digest', 'size_in_bytes'):
            assert artifact[key] == expected[key], (version, key)
        assert len(expected['members']) == 4
        names.update(expected['members'])
    assert len(names) == 64
    before, _ = release_assets(version)
    save(f'{version}-before.json', before)
    save(f'{version}-preflight.json', {'run': run['id'], 'head': run['head_sha'],
                                    'artifacts': config['artifacts']})


def publish(version, config):
    receipts = []
    public_sample = None
    for artifact in config['artifacts']:
        with tempfile.TemporaryDirectory(prefix='php-publication-') as temp:
            folder = Path(temp)
            archive = folder / 'source.zip'
            download_artifact(artifact, archive)
            files = []
            with zipfile.ZipFile(archive) as source:
                assert set(source.namelist()) == set(artifact['members']), artifact['name']
                for name in artifact['members']:
                    assert Path(name).name == name
                    target = folder / name
                    with source.open(name) as stream, target.open('wb') as output:
                        shutil.copyfileobj(stream, output, 1024 * 1024)
                    # Reading each member completely also verifies its ZIP CRC.
                    if name in config['audited_members']:
                        assert digest(target) == config['audited_members'][name], name
                    files.append(target)
            result = upload(version, files, {'run': config['run'], 'head': config['head'],
                                            'artifact_id': artifact['id'],
                                            'artifact_digest': artifact['digest']})
            receipts.extend(result)
            save(f'{version}-assets.json', receipts)
            if public_sample is None:
                item = next(item for item in result
                            if item['name'].endswith('.tar.zst') and '-dbgsym' not in item['name'])
                downloaded = folder / 'public.tar.zst'
                subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location',
                                '--retry', '5', '--output', str(downloaded), item['url']], check=True)
                assert digest(downloaded) == item['digest']
                public_sample = item
            print(f'{version}: verified and published {artifact["name"]}', flush=True)
    assert len(receipts) == 64
    with tempfile.TemporaryDirectory(prefix='php-release-metadata-') as temp:
        folder = Path(temp)
        installer = folder / 'install.sh'
        shutil.copyfile('scripts/install.sh', installer)
        version_log = folder / f'php{version}.log'
        full_version = config['full_version']
        version_log.write_text(('' if '-dev' in full_version else 'php-') + full_version + '\n')
        build_log = folder / 'build.log'
        _, assets = release_assets(version)
        if 'build.log' in assets:
            gh('release', 'download', version, '--repo', REPO, '--pattern', 'build.log',
               '--dir', str(folder))
        previous = build_log.read_text() if build_log.exists() else ''
        day = datetime.datetime.now(datetime.timezone.utc).strftime('%Y.%m.%d')
        build_log.write_text(previous.rstrip('\n') + '\n' + day + '\n')
        receipts.extend(upload(version, [installer, version_log, build_log],
                               {'commit': config['merged_commit']}))
        public_installer = folder / 'public-install.sh'
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location',
                        '--retry', '5', '--output', str(public_installer),
                        f'https://github.com/{REPO}/releases/download/{version}/install.sh'], check=True)
        assert digest(public_installer) == config['installer_digest']
    after, assets = release_assets(version)
    before = json.loads((RECEIPTS / f'{version}-before.json').read_text())
    published = {item['name'] for item in receipts}
    for item in before['assets']:
        if item['name'] not in published:
            assert assets[item['name']]['id'] == item['id'], item['name']
    save(f'{version}-after.json', after)
    save(f'{version}-complete.json', {'php': version, 'run': config['run'],
                                    'head': config['head'], 'assets': receipts,
                                    'anonymous_archive_verified': public_sample,
                                    'anonymous_installer_verified': True,
                                    'unrelated_assets_preserved': True})
    print(f'{version}: all 64 archives and release metadata verified', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('php')
    parser.add_argument('--preflight-only', action='store_true')
    args = parser.parse_args()
    configuration = json.loads((ROOT / 'manifest.json').read_text())[args.php]
    preflight(args.php, configuration)
    if not args.preflight_only:
        publish(args.php, configuration)
