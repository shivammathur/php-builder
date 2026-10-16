"""Private R2 transport. Kept identical in php-builder and php-ubuntu.

curl signs S3 requests; credentials enter through stdin, never command arguments.
Conditional writes are immutable and every upload is downloaded and verified.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
from urllib.parse import quote, urlencode
import xml.etree.ElementTree as ET

BUCKET = "php-darwin-private"
PREFIXES = {"php-builder": "php-builder/uploads", "php-ubuntu": "php-ubuntu/builds"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def build_id(value):
    require(isinstance(value, str) and re.fullmatch(r"[1-9][0-9]*-[1-9][0-9]*", value), "Invalid build ID")
    return value


def prefix(repo, ident):
    return f"{PREFIXES[repo]}/{build_id(ident)}"


def workdir():
    root = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())).resolve()
    work = root / "php-private"
    require(not work.is_symlink(), "Private workspace must not be a symlink")
    work.mkdir(mode=0o700, exist_ok=True)
    return work


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def fingerprint(file):
    h = hashlib.sha256()
    size = 0
    with open(file, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
            size += len(chunk)
    return {"sha256": h.hexdigest(), "bytes": size}


class Store:
    def __init__(self):
        self.endpoint = os.environ["PRIVATE_R2_ENDPOINT"].rstrip("/")
        require(re.fullmatch(r"https://[a-f0-9]{32}\.r2\.cloudflarestorage\.com", self.endpoint), "Invalid private R2 endpoint")
        key = os.environ["PRIVATE_R2_ACCESS_KEY_ID"]
        secret = os.environ["PRIVATE_R2_SECRET_ACCESS_KEY"]
        require(re.fullmatch(r"[A-Za-z0-9]+", key) and re.fullmatch(r"[A-Za-z0-9]+", secret), "Invalid private credentials")
        self.config = f'user = "{key}:{secret}"\n'.encode()

    def request(self, method, key, output, source=None, query=None):
        require(not key.startswith("/") and ".." not in key.split("/"), "Invalid R2 key")
        url = f"{self.endpoint}/{BUCKET}/{quote(key, safe='/~')}"
        if query:
            url += "?" + urlencode(sorted(query.items()), quote_via=quote)
        args = ["curl", "--disable", "--silent", "--show-error", "--config", "-", "--aws-sigv4", "aws:amz:auto:s3",
                "--proto", "=https", "--connect-timeout", "20", "--max-time", "900", "--max-filesize", str(2 * 1024**3),
                "--request", method, "--output", str(output), "--write-out", "%{http_code}"]
        if source is not None:
            # curl appends a local filename to upload URLs ending in '/'.
            transfer = ["--data-binary", "@" + str(source)] if key.endswith("/") else ["--upload-file", str(source)]
            args += transfer + ["--header", "If-None-Match: *", "--header", "Cache-Control: private, no-store",
                     "--header", "x-amz-content-sha256: " + fingerprint(source)["sha256"]]
        args += [url]
        for attempt in range(4):
            result = subprocess.run(args, input=self.config, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            status = int(result.stdout or b"0")
            if result.returncode == 0 and status not in (429, 500, 502, 503, 504):
                return status
            if attempt < 3:
                time.sleep(2 ** attempt)
        raise RuntimeError(f"Private R2 transfer failed ({method}, HTTP {status})")

    def get(self, key, output, expected=None):
        output = Path(output)
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as tmp:
            temporary = Path(tmp.name)
        try:
            require(self.request("GET", key, temporary) == 200, "Private object is unavailable: " + key)
            actual = fingerprint(temporary)
            require(expected is None or actual == expected, "Private object checksum/size mismatch")
            temporary.replace(output)
            return actual
        finally:
            temporary.unlink(missing_ok=True)

    def put(self, key, source):
        expected = fingerprint(source)
        with tempfile.TemporaryDirectory(dir=workdir()) as tmp:
            response = Path(tmp) / "response"
            require(self.request("PUT", key, response, source) in (200, 201, 412), "Private upload failed")
            self.get(key, Path(tmp) / "verify", expected)
        return expected

    def get_json(self, key):
        with tempfile.TemporaryDirectory(dir=workdir()) as tmp:
            file = Path(tmp) / "record.json"
            self.get(key, file)
            require(file.stat().st_size <= 8 * 1024**2, "Private record is too large")
            return json.loads(file.read_bytes())

    def put_json(self, key, value):
        with tempfile.TemporaryDirectory(dir=workdir()) as tmp:
            file = Path(tmp) / "record.json"
            file.write_bytes(canonical(value))
            return self.put(key, file)

    def list(self, start):
        keys, token = [], ""
        while True:
            query = {"list-type": "2", "prefix": start}
            if token:
                query["continuation-token"] = token
            with tempfile.TemporaryDirectory(dir=workdir()) as tmp:
                file = Path(tmp) / "list.xml"
                require(self.request("GET", "", file, query=query) == 200, "Cannot list private uploads")
                root = ET.fromstring(file.read_bytes())
            ns = {"s": "http://s3.amazonaws.com/doc/2006-03-01/"}
            keys += [item.text for item in root.findall("s:Contents/s:Key", ns)]
            token = root.findtext("s:NextContinuationToken", default="", namespaces=ns)
            if not token:
                return keys
