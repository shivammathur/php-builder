"""Authenticated staging contract shared with php-ubuntu. No executable inputs."""
import hashlib
import hmac
import os
from pathlib import Path, PurePosixPath
import re
import tarfile

from store import build_id, canonical, digest, fingerprint, prefix, require

SAPIS = ["apache2", "cgi", "cli", "embed", "fpm", "phpdbg"]
CONTAINERS = ["ubuntu:22.04", "ubuntu:24.04", "ubuntu:26.04", "arm64v8/ubuntu:22.04", "arm64v8/ubuntu:24.04", "arm64v8/ubuntu:26.04", "debian:12", "debian:trixie"]
HEX = re.compile(r"[a-f0-9]{64}")


def target(container):
    require(container in CONTAINERS, "Unsupported container")
    arch = "arm64" if container.startswith("arm64v8/") else "amd64"
    dist, version = container.removeprefix("arm64v8/").split(":")
    version = "13" if version == "trixie" else version
    return {"container": container, "dist": dist, "version": version, "arch": arch,
            "runner": "ubuntu-24.04" + ("-arm" if arch == "arm64" else ""),
            "os": f"{dist}-{version}" + ("-arm" if arch == "arm64" else "")}


def source_name(name, minor):
    match = re.fullmatch(r"php-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.(xz|gz)", name)
    require(match and match[1].rsplit(".", 1)[0] == minor, "Source filename does not match PHP minor")
    return {"name": name, "version": match[1], "url": "https://www.php.net/distributions/" + name}


def validate_source(file, source):
    require(Path(file).stat().st_size <= 256 * 1024**2, "Source archive is too large")
    root = "php-" + source["version"]
    total, header, configure = 0, None, False
    with tarfile.open(file) as archive:
        for member in archive:
            parts = PurePosixPath(member.name).parts
            require(parts and parts[0] == root and ".." not in parts and not member.name.startswith("/"), "Unsafe source archive path")
            require(member.isfile() or member.isdir(), "Source archive must contain only regular files/directories")
            total += member.size
            require(total <= 2 * 1024**3, "Expanded source is too large")
            if member.name == root + "/main/php_version.h":
                require(member.size < 65536, "Invalid version header")
                header = archive.extractfile(member).read().decode()
            if member.name == root + "/configure" and member.isfile():
                configure = True
    require(configure and header is not None and re.search(r'^#define PHP_VERSION "' + re.escape(source["version"]) + r'"$', header, re.M), "Source version/configure mismatch")
    return fingerprint(file)


def matrices(repo, containers):
    packages, tests, sapis = [], [], []
    for container in containers:
        t = target(container)
        require(repo == "php-builder" or t["dist"] == "ubuntu", "Ubuntu staging only accepts Ubuntu targets")
        for ts in ("nts", "zts"):
            base = {**t, "ts": ts, "id": f'{t["dist"]}-{t["version"]}-{t["arch"]}-{ts}'}
            if repo == "php-builder":
                packages.append(base)
                sapis += [{**base, "sapi": sapi, "id": base["id"] + "-" + sapi} for sapi in SAPIS]
            for mode in ("release", "debug"):
                item = {**base, "mode": mode, "id": base["id"] + "-" + mode}
                if repo == "php-ubuntu":
                    packages.append(item)
                if repo == "php-builder":
                    tests.append({**item, "kind": "container", "id": item["id"] + "-container"})
                if t["dist"] == "ubuntu":
                    tests.append({**item, "kind": "host", "id": item["id"] + "-host"})
    return {"packages": packages, "tests": tests, "sapis": sapis}


def filenames(plan, item):
    suffix = "_arm64" if item["arch"] == "arm64" else ""
    platform = item["dist"] + item["version"] + suffix
    minor = plan["php_version"]
    if plan["project"] == "php-builder":
        ts = "-zts" if item["ts"] == "zts" else ""
        return [f"php_{minor}{ts}{debug}+{platform}.tar.{ext}" for debug in ("", "-dbgsym") for ext in ("xz", "zst")]
    debug = "-dbgsym" if item["mode"] == "debug" else ""
    return [f'php_{ver}-{item["ts"]}{debug}+{platform}.tar.zst' for ver in (minor, plan["source"]["version"])]


def validate_plan(plan, repo, ident):
    require(plan.get("schema") == 1 and plan.get("project") == repo and plan.get("id") == build_id(ident), "Invalid private plan identity")
    require(plan.get("repository") == "shivammathur/" + repo and re.fullmatch(r"[a-f0-9]{40}", plan.get("revision", "")), "Invalid plan repository/revision")
    source = source_name(plan["source"]["name"], plan["php_version"])
    require(all(plan["source"].get(k) == v for k, v in source.items()), "Invalid source identity")
    require(HEX.fullmatch(plan["source"]["sha256"]) and 0 < plan["source"]["bytes"] <= 256 * 1024**2, "Invalid source digest")
    containers = plan["containers"]
    require(containers and len(set(containers)) == len(containers), "Invalid target selection")
    expected = matrices(repo, containers)
    require(all(plan.get(k) == v for k, v in expected.items()), "Incomplete build/test matrix")
    require(HEX.fullmatch(plan["installer"]["sha256"]) and 0 < plan["installer"]["bytes"] < 1024**2, "Invalid installer")
    if repo == "php-builder":
        require(re.fullmatch(r"[a-f0-9]{40}", plan.get("php_build_commit", "")), "Invalid php-build pin")
    else:
        build_id(plan["builder_id"])
        require(HEX.fullmatch(plan["builder_ready_sha256"]), "Invalid upstream approval digest")
    return plan


def sign(payload, secret):
    require(HEX.fullmatch(secret or ""), "Missing signing key")
    return hmac.new(bytes.fromhex(secret), canonical(payload), hashlib.sha256).hexdigest()


def validate_result(record, plan, item, kind):
    require(record.get("id") == item["id"] and record.get("plan_sha256") == digest(plan) and record.get("status") == "success", "Unverified staging result")
    if kind == "packages":
        files = record["files"]
        require(sorted(f["name"] for f in files) == sorted(filenames(plan, item)), "Incomplete package files")
        for file in files:
            require(HEX.fullmatch(file["sha256"]) and 0 < file["bytes"] < 2 * 1024**3, "Invalid package digest")
        if plan["project"] == "php-ubuntu":
            require(files[0]["sha256"] == files[1]["sha256"] and files[0]["bytes"] == files[1]["bytes"], "Minor and full-version caches differ")
    return record


def verify_ready(record, repo, ident, secret, allow_branch=False):
    require(isinstance(record.get("signature"), str) and hmac.compare_digest(record["signature"], sign(record["payload"], secret)), "Approval signature mismatch")
    payload = record["payload"]
    plan = validate_plan(payload["plan"], repo, ident)
    require(allow_branch or plan["ref"] == "refs/heads/main", "Production promotion requires a build from main")
    for kind in ("packages", "tests"):
        require(len(payload[kind]) == len(plan[kind]), "Incomplete approval results")
        require(len({r["id"] for r in payload[kind]}) == len(plan[kind]), "Duplicate approval results")
        for item in plan[kind]:
            record = next((r for r in payload[kind] if r["id"] == item["id"]), {})
            validate_result(record, plan, item, kind)
            if kind == "tests":
                package = package_for_test(plan, item)
                result = next(r for r in payload["packages"] if r["id"] == package["id"])
                require(record["package_sha256"] == digest(result), "Tests do not match the approved package")
    return payload


def package_for_test(plan, item):
    return next(p for p in plan["packages"] if all(p[k] == item[k] for k in ("container", "ts")) and (plan["project"] == "php-builder" or p["mode"] == item["mode"]))
