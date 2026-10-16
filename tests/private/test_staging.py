import contextlib
import copy
import importlib.util
import io
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/private"))
import protocol as p
import publish_guard
import run as private_run
from store import build_id, digest, fingerprint


def approved(repo="php-builder", ref="refs/heads/main"):
    plan = {"schema": 1, "project": repo, "repository": "shivammathur/" + repo, "id": "123-1",
            "revision": "a" * 40, "ref": ref, "php_version": "8.4", "containers": ["ubuntu:24.04", "arm64v8/ubuntu:24.04"],
            "source": {**p.source_name("php-8.4.27.tar.xz", "8.4"), "sha256": "b" * 64, "bytes": 42},
            "installer": {"name": "install.sh", "sha256": "c" * 64, "bytes": 12}, "php_build_commit": "d" * 40,
            "builder_id": "456-1", "builder_ready_sha256": "e" * 64}
    plan.update(p.matrices(repo, plan["containers"]))
    packages = [{"id": item["id"], "plan_sha256": digest(plan), "status": "success",
                 "files": [{"name": name, "sha256": "f" * 64, "bytes": 10} for name in p.filenames(plan, item)]} for item in plan["packages"]]
    tests = []
    for item in plan["tests"]:
        package = p.package_for_test(plan, item)
        result = next(r for r in packages if r["id"] == package["id"])
        tests.append({"id": item["id"], "status": "success", "plan_sha256": digest(plan), "package_sha256": digest(result)})
    payload = {"plan": plan, "packages": packages, "tests": tests}
    return {"payload": payload, "signature": p.sign(payload, "1" * 64)}


class ProtocolTests(unittest.TestCase):
    def test_full_matrices_and_matching_upstream_names(self):
        for repo, packages, tests in [("php-builder", 4, 16), ("php-ubuntu", 8, 8)]:
            result = p.verify_ready(approved(repo), repo, "123-1", "1" * 64)
            self.assertEqual((len(result["packages"]), len(result["tests"])), (packages, tests))
        bp = approved()["payload"]["plan"]
        for item in approved("php-ubuntu")["payload"]["plan"]["packages"]:
            self.assertIn(p.package_for_test(bp, item), bp["packages"])

    def test_signature_branch_and_wrong_repository(self):
        record = approved()
        record["payload"]["plan"]["ref"] = "refs/heads/feature/test"
        with self.assertRaises(ValueError): p.verify_ready(record, "php-builder", "123-1", "1" * 64)
        record = approved(ref="refs/heads/feature/test")
        p.verify_ready(record, "php-builder", "123-1", "1" * 64, allow_branch=True)
        with self.assertRaises(ValueError): p.verify_ready(record, "php-builder", "123-1", "1" * 64)
        with self.assertRaises(ValueError): p.verify_ready(approved(), "php-ubuntu", "123-1", "1" * 64)

    def test_missing_duplicate_and_mismatched_tests(self):
        for mutation in [lambda r: r["tests"].pop(), lambda r: r["tests"].__setitem__(0, r["tests"][1]),
                         lambda r: r["tests"][0].update(package_sha256="0" * 64),
                         lambda r: r["packages"][0]["files"].pop(),
                         lambda r: r["plan"]["packages"].pop()]:
            record = approved()
            mutation(record["payload"])
            record["signature"] = p.sign(record["payload"], "1" * 64)
            with self.assertRaises((ValueError, StopIteration)): p.verify_ready(record, "php-builder", "123-1", "1" * 64)

    def test_invalid_inputs_and_ubuntu_alias_mismatch(self):
        for bad in ("../123-1", "123/1", "0-1", "123-0"):
            with self.assertRaises(ValueError): build_id(bad)
        for bad in ("evil/image:latest", "ubuntu:latest", "ubuntu:24.04;id"):
            with self.assertRaises(ValueError): p.target(bad)
        with self.assertRaises(ValueError): p.source_name("php-8.5.1.tar.xz", "8.4")
        record = approved("php-ubuntu")
        record["payload"]["packages"][0]["files"][0]["sha256"] = "0" * 64
        record["signature"] = p.sign(record["payload"], "1" * 64)
        with self.assertRaises(ValueError): p.verify_ready(record, "php-ubuntu", "123-1", "1" * 64)

    def test_source_versions_and_traversal(self):
        for extension in ("xz", "gz"):
            for member, version, valid in [("configure", "8.4.27", True), ("../escape", "8.4.27", False), ("configure", "8.4.26", False)]:
                with tempfile.TemporaryDirectory() as tmp:
                    file = Path(tmp, "php-8.4.27.tar." + extension)
                    with tarfile.open(file, "w:" + extension) as archive:
                        for name, data in [(member, b"#!/bin/sh\n"), ("main/php_version.h", ('#define PHP_VERSION "' + version + '"\n').encode())]:
                            info = tarfile.TarInfo("php-8.4.27/" + name); info.size = len(data)
                            archive.addfile(info, io.BytesIO(data))
                    if valid: self.assertEqual(p.validate_source(file, p.source_name(file.name, "8.4")), fingerprint(file))
                    else:
                        with self.assertRaises(ValueError): p.validate_source(file, p.source_name(file.name, "8.4"))


class LoggingTests(unittest.TestCase):
    def test_child_output_and_workflow_commands_never_reach_console(self):
        for child_exit, transfer_fails in [(0, False), (1, False), (0, True)]:
            with tempfile.TemporaryDirectory() as tmp:
                uploaded = []
                class FakeStore:
                    def put(self, key, file):
                        uploaded.append(Path(file).read_text())
                        if transfer_fails: raise RuntimeError("private credential detail")
                output = io.StringIO()
                with patch.dict(os.environ, {"RUNNER_TEMP": tmp, "PRIVATE_PROJECT": "php-builder", "PRIVATE_BUILD_ID": "123-1", "GITHUB_ACTIONS": "false"}), patch.object(private_run, "Store", FakeStore), patch.object(sys, "argv", ["run.py", "test-logs", sys.executable, "-c", f'print("::error::embargoed-version");raise SystemExit({child_exit})']), contextlib.redirect_stdout(output):
                    status = private_run.main()
                self.assertEqual(status, 1 if child_exit or transfer_fails else 0)
                self.assertIn("embargoed-version", uploaded[0])
                self.assertNotIn("embargoed-version", output.getvalue())
                self.assertNotIn("credential", output.getvalue())


    def test_github_file_commands_are_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            names = ("GITHUB_STEP_SUMMARY", "GITHUB_ENV", "GITHUB_PATH", "GITHUB_STATE", "GITHUB_OUTPUT")
            public = {name: str(Path(tmp, name)) for name in names}
            for file in public.values(): Path(file).touch()
            uploaded = []
            class FakeStore:
                def put(self, key, file): uploaded.append(Path(file).read_text())
            command = 'import os;from pathlib import Path;' + ';'.join(f'Path(os.environ[{name!r}]).write_text("embargoed-version")' for name in names)
            with patch.dict(os.environ, {**public, "RUNNER_TEMP": tmp, "PRIVATE_PROJECT": "php-builder", "PRIVATE_BUILD_ID": "123-1", "GITHUB_ACTIONS": "false"}), patch.object(private_run, "Store", FakeStore), patch.object(sys, "argv", ["run.py", "test-files", sys.executable, "-c", command]), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(private_run.main(), 0)
            self.assertTrue(all(Path(file).read_text() == "" for file in public.values()))
            self.assertIn("embargoed-version", uploaded[0])

    def test_plan_retains_validated_matrix_output_channel(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp, "matrix")
            class FakeStore:
                def put(self, key, file): pass
            command = 'import os;from pathlib import Path;Path(os.environ["GITHUB_OUTPUT"]).write_text("packages={}")'
            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output), "RUNNER_TEMP": tmp, "PRIVATE_PROJECT": "php-builder", "PRIVATE_BUILD_ID": "123-1", "GITHUB_ACTIONS": "false"}), patch.object(private_run, "Store", FakeStore), patch.object(sys, "argv", ["run.py", "plan", sys.executable, "-c", command]), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(private_run.main(), 0)
            self.assertEqual(output.read_text(), "packages={}")


class PublicationTests(unittest.TestCase):
    def test_existing_ci_installer_patches_remain_valid(self):
        source = (ROOT / "scripts/install.sh").read_text()
        project = json.loads((ROOT / "scripts/private/project.json").read_text())["project"]
        lines = source.splitlines()
        if project == "php-builder":
            lines = [line for line in lines if "download" not in line]
        else:
            lines = [line for line in lines if "releases" not in line and not re.fullmatch(r"\s*fix_packages\s*", line)]
        result = subprocess.run(["bash", "-n"], input="\n".join(lines), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_builder_uses_archive_version_and_rejects_downgrade(self):
        info = {"assets": [{"name": "php8.4.log", "browser_download_url": "https://example.invalid/version"}]}
        def command(args, **kwargs):
            return '#define PHP_VERSION "8.4.26"\n' if args[0] == "tar" else "php-8.4.27\n"
        with patch.object(publish_guard, "release_info", return_value=info), patch.object(subprocess, "check_output", side_effect=command):
            with self.assertRaises(ValueError): publish_guard.builder("8.4", ["archive.zst"])

    def test_ubuntu_accepts_all_version_and_build_suffixes(self):
        for version in ("8.4.26", "8.6.0RC1", "8.6.0-dev"):
            with tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp, "job"); directory.mkdir()
                minor = ".".join(version.split(".")[:2])
                for ts in ("nts", "zts"):
                    for debug in ("", "-dbgsym"):
                        for arch in ("", "_arm64"):
                            suffix = f"-{ts}{debug}+ubuntu24.04{arch}.tar.zst"
                            Path(directory, "php_" + version + suffix).write_bytes(b"cache")
                            Path(directory, "php_" + minor + suffix).write_bytes(b"cache")
                with patch.object(publish_guard, "release_info", return_value=None):
                    publish_guard.ubuntu(tmp)

    def test_ubuntu_minor_and_semver_pair_must_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp, "job"); directory.mkdir()
            Path(directory, "php_8.4-nts+ubuntu24.04.tar.zst").write_bytes(b"old")
            Path(directory, "php_8.4.27-nts+ubuntu24.04.tar.zst").write_bytes(b"new")
            with self.assertRaises(ValueError): publish_guard.ubuntu(tmp)


if __name__ == "__main__":
    unittest.main()
