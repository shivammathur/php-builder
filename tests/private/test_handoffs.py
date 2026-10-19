"""Privacy boundaries for inter-job storage and workflow execution."""
import os
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/private"))
from store import Store, fingerprint


class PrivateHandoffTests(unittest.TestCase):
    def test_workflows_never_use_github_artifacts_caches_or_publishers(self):
        for name in ("stage-private.yml", "cleanup-private.yml"):
            text = (ROOT / ".github/workflows" / name).read_text()
            self.assertNotRegex(text, r"actions/(?:upload-artifact|download-artifact|cache)@|gh\s+(?:release|run download)|scripts/release\.sh")
            self.assertIn("scripts/private/run.py", text)
            if name == "stage-private.yml":
                self.assertNotIn("contents: write", text)
                self.assertNotIn("secrets.TOKEN", text)

    def test_signatures_match_aws_sdk_for_listing_and_streamed_package_upload(self):
        # Golden signatures independently checked with botocore S3SigV4Auth.
        endpoint = "https://" + "a" * 32 + ".r2.cloudflarestorage.com"
        with patch.dict(os.environ, {"PRIVATE_R2_ENDPOINT": endpoint,
                                   "PRIVATE_R2_ACCESS_KEY_ID": "EXAMPLEKEY",
                                   "PRIVATE_R2_SECRET_ACCESS_KEY": "EXAMPLESECRET"}):
            store = Store()
            cases = [
                ("GET", "/php-darwin-private/?list-type=2&prefix=uploads%2F", b"",
                 "b8dbbb13449b21bbb078560672e68c3f68bbf5aa78d01ac6ee4833a0133cce48"),
                ("PUT", "/php-darwin-private/php-builder/uploads/123-1/packages/php_8.4%2Bubuntu24.04.tar.zst", b"package",
                 "e870b898ef85dd53c7ec38f32ba1e9e2726a60a7dd75e08a2cf9498d0c591785"),
            ]
            for method, path, payload, expected in cases:
                checksum = hashlib.sha256(payload).hexdigest()
                config = store.signed_config(method, endpoint + path, checksum, "20261019T170000Z").decode()
                self.assertIn("Signature=" + expected, config)
                self.assertIn("x-amz-content-sha256: " + checksum, config)
                self.assertNotIn("EXAMPLESECRET", config)

    def test_r2_handoff_is_immutable_and_consumers_reject_changed_bytes(self):
        objects = {}
        def request(_self, method, key, output, source=None, query=None):
            if method == "PUT":
                if key in objects: return 412
                objects[key] = Path(source).read_bytes()
                return 200
            if key not in objects: return 404
            Path(output).write_bytes(objects[key])
            return 200
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {
            "RUNNER_TEMP": tmp, "PRIVATE_R2_ENDPOINT": "https://" + "a" * 32 + ".r2.cloudflarestorage.com",
            "PRIVATE_R2_ACCESS_KEY_ID": "test", "PRIVATE_R2_SECRET_ACCESS_KEY": "test",
        }), patch.object(Store, "request", request):
            archive = Path(tmp, "archive"); archive.write_bytes(b"verified private package")
            expected = Store().put("php-builder/uploads/123-1/packages/archive.zst", archive)
            download = Path(tmp, "next-job/archive")
            Store().get("php-builder/uploads/123-1/packages/archive.zst", download, expected)
            self.assertEqual(fingerprint(download), expected)
            archive.write_bytes(b"different candidate")
            with self.assertRaisesRegex(ValueError, "checksum/size"):
                Store().put("php-builder/uploads/123-1/packages/archive.zst", archive)
            objects["php-builder/uploads/123-1/packages/archive.zst"] = b"corrupted package"
            with self.assertRaisesRegex(ValueError, "checksum/size"):
                Store().get("php-builder/uploads/123-1/packages/archive.zst", download, expected)
            self.assertEqual(fingerprint(download), expected)


if __name__ == "__main__":
    unittest.main()
