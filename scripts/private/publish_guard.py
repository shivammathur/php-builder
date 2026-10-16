"""Reject stale queued publications, using the version in the actual artifacts."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from store import fingerprint, require


def release_info(repo, tag):
    result = subprocess.run(["gh", "api", f"repos/{repo}/releases/tags/{tag}"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        require(b"404" in result.stderr, "Cannot verify current public release")
        return None
    return json.loads(result.stdout)


def stable(value):
    match = re.fullmatch(r"(?:php-)?([0-9]+)\.([0-9]+)\.([0-9]+)", value.strip())
    return tuple(map(int, match.groups())) if match else None


def builder(minor, files):
    versions = set()
    for file in files:
        if file.endswith(".zst"):
            header = subprocess.check_output(["tar", "-I", "zstd", "-xOf", file, "--wildcards", "./usr/include/php/*/main/php_version.h"], text=True)
            match = re.search(r'^#define PHP_VERSION "([^"\n]+)"$', header, re.M)
            require(match is not None, "Archive has no PHP version header")
            versions.add(match[1])
    require(len(versions) == 1, "Publication mixes PHP source versions or has no verified Zstandard archives")
    version = versions.pop()
    require(version.startswith(minor + "."), "Archive has the wrong PHP minor")
    require(not os.environ.get("PHP_PRIVATE_RELEASE_VERSION") or os.environ["PHP_PRIVATE_RELEASE_VERSION"] == version, "Approved version differs from archive")
    info = release_info("shivammathur/php-builder", minor)
    if info:
        asset = next((a for a in info["assets"] if a["name"] == "php" + minor + ".log"), None)
        if asset:
            old = subprocess.check_output(["curl", "--disable", "-fsSL", "--retry", "2", asset["browser_download_url"]], text=True)
            if stable(old):
                require(stable(version) is not None and stable(version) >= stable(old), "Refusing to replace a newer public PHP release")
    print(("php-" if stable(version) else "") + version)


def ubuntu(directory):
    files = list(Path(directory).glob("*/*.tar.zst"))
    require(files, "No PHP cache archives to publish")
    versions = {}
    for file in files:
        match = re.fullmatch(r"php_([0-9]+\.[0-9]+\.[0-9]+(?:[a-zA-Z][a-zA-Z0-9]*)?(?:-[a-zA-Z0-9]+)?)(-(?:nts|zts)(?:-dbgsym)?\+ubuntu[^/]+\.tar\.zst)", file.name)
        if not match:
            continue
        version, suffix = match.groups()
        minor = version.rsplit(".", 1)[0]
        paired = file.with_name("php_" + minor + suffix)
        require(paired.is_file() and fingerprint(paired) == fingerprint(file), "Full-version and minor cache archives differ")
        versions.setdefault(minor, set()).add(version)
    require(versions and all(len(v) == 1 for v in versions.values()), "Cache publication mixes PHP versions")
    expected = os.environ.get("PHP_PRIVATE_RELEASE_VERSION")
    require(not expected or all(v == {expected} for v in versions.values()), "Approved PHP version differs from cache")
    info = release_info("shivammathur/php-ubuntu", "builds")
    if not info:
        return
    names = subprocess.check_output(["gh", "api", "--paginate", f'repos/shivammathur/php-ubuntu/releases/{info["id"]}/assets?per_page=100', "--jq", ".[].name"], text=True).splitlines()
    for minor, values in versions.items():
        current = stable(next(iter(values)))
        if current is None:
            continue
        for name in names:
            match = re.match(r"php_(" + re.escape(minor) + r"\.[0-9]+)-", name)
            if match:
                require(current >= stable(match[1]), "Refusing to replace a newer public Ubuntu PHP cache")


if __name__ == "__main__":
    if sys.argv[1] == "ubuntu":
        ubuntu(sys.argv[2])
    else:
        builder(sys.argv[1], sys.argv[2:])
