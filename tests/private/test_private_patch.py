import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/private'))
import protocol
import stage
from store import fingerprint
from test_staging import approved


class PrivatePatchTests(unittest.TestCase):
    def test_patch_identity_is_bound_to_version_and_has_bounded_contents(self):
        plan = approved()['payload']['plan']
        plan['private_patch'] = {'name': 'php-8.4.patch', 'sha256': 'a' * 64, 'bytes': 123}
        protocol.validate_plan(plan, 'php-builder', '123-1')
        for change in [{'name': '../php-8.4.patch'}, {'name': 'php-7.4.patch'}, {'sha256': ''},
                       {'bytes': 0}, {'bytes': True}, {'bytes': 16 * 1024**2 + 1}]:
            invalid = copy.deepcopy(plan)
            invalid['private_patch'].update(change)
            with self.assertRaises(ValueError): protocol.validate_plan(invalid, 'php-builder', '123-1')
        ubuntu = approved('php-ubuntu')['payload']['plan']
        ubuntu['private_patch'] = plan['private_patch']
        with self.assertRaises(ValueError): protocol.validate_plan(ubuntu, 'php-ubuntu', '123-1')

    def test_r2_patch_plan_checks_expected_hash_and_snapshots_exact_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            archive = tmp / 'base.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name, data in [('configure', b'fixture'), ('main/php_version.h', b'#define PHP_VERSION "8.4.99"\n')]:
                    member = tarfile.TarInfo('php-8.4.99/' + name); member.size = len(data); tar.addfile(member, io.BytesIO(data))
            patch_bytes = b'private synthetic patch fixture\n'
            sha = hashlib.sha256(patch_bytes).hexdigest()
            class FakeStore:
                def __init__(self): self.uploads = {}; self.plans = []
                def get(self, key, dest):
                    data = patch_bytes if key == 'uploads/patches/php-8.4.patch' else archive.read_bytes()
                    Path(dest).write_bytes(data)
                def put(self, key, file): self.uploads[key] = Path(file).read_bytes()
                def put_json(self, key, value): self.plans.append(value)
            event = tmp / 'event.json'
            env = {'PRIVATE_BUILD_ID': '123-1', 'PHP_VERSION': '8.4', 'GITHUB_REPOSITORY': 'shivammathur/php-builder',
                   'GITHUB_SHA': 'a' * 40, 'GITHUB_REF': 'refs/heads/feature/private-r2-releases',
                   'GITHUB_EVENT_PATH': str(event), 'GITHUB_OUTPUT': str(tmp / 'output'), 'RUNNER_TEMP': str(tmp)}
            for expected, valid in [(sha, True), ('b' * 64, False), ('', False)]:
                event.write_text(json.dumps({'inputs': {'source-file': 'builder-base/php-8.4.99.tar.gz',
                    'patch-file': 'php-8.4.patch', 'patch-sha256': expected, 'containers': 'ubuntu:24.04'}}))
                store = FakeStore()
                with patch.dict(os.environ, env), patch.object(stage, 'PROJECT', 'php-builder'), patch.object(stage, 'github', return_value={'sha': 'c' * 40}):
                    if valid: stage.plan_build(store)
                    else:
                        with self.assertRaises(ValueError): stage.plan_build(store)
                if valid:
                    self.assertEqual(store.plans[0]['private_patch'], {'name': 'php-8.4.patch', 'sha256': sha, 'bytes': len(patch_bytes)})
                    self.assertEqual(store.uploads['php-builder/uploads/123-1/inputs/php-8.4.patch'], patch_bytes)
                else: self.assertFalse(store.plans)

    def test_private_patch_is_last_and_changed_bytes_stop_before_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp); archive = tmp / 'source.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                member = tarfile.TarInfo('php-8.4.99/example'); member.size = 5; tar.addfile(member, io.BytesIO(b'base\n'))
            public = tmp / 'public.patch'; private = tmp / 'private.patch'
            public.write_text('--- a/example\n+++ b/example\n@@ -1 +1 @@\n-base\n+distribution\n')
            private.write_text('--- a/example\n+++ b/example\n@@ -1 +1 @@\n-distribution\n+private\n')
            script = '''set -eu
PATCH_FILES="$PUBLIC_PATCH"
patch_file() { PATCH_FILES="$PATCH_FILES $1"; }
build_package() { for file in $PATCH_FILES; do patch --batch --forward -p1 < "$file"; done; test "$(cat example)" = private; }
source scripts/private/source.sh
install_package_from_private
'''
            env = {**os.environ, 'PUBLIC_PATCH': str(public), 'PHP_PRIVATE_SOURCE_ARCHIVE': str(archive),
                   'PHP_PRIVATE_SOURCE_SHA256': fingerprint(archive)['sha256'], 'PHP_BUILD_TMPDIR': str(tmp / 'work'),
                   'DEFINITION': '8.4', 'PHP_PRIVATE_PATCH_FILE': str(private), 'PHP_PRIVATE_PATCH_SHA256': fingerprint(private)['sha256']}
            result = subprocess.run(['bash', '-c', script], cwd=ROOT, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            private.write_text(private.read_text() + 'tampered\n')
            env['PHP_BUILD_TMPDIR'] = str(tmp / 'failed')
            result = subprocess.run(['bash', '-c', script], cwd=ROOT, env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((tmp / 'failed').exists())


if __name__ == '__main__': unittest.main()
