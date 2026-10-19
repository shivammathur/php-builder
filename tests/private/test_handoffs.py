"""Privacy boundaries for inter-job storage and workflow execution."""
import os
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
