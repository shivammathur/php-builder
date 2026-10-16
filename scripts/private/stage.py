#!/usr/bin/env python3
"""Stage, verify, promote and archive private builds in either Linux repository."""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.request import Request, urlopen

from store import Store, build_id, canonical, digest, fingerprint, prefix, require, workdir
from protocol import (CONTAINERS, SAPIS, filenames, matrices, package_for_test, sign,
                      source_name, validate_plan, validate_result, validate_source, verify_ready)

PROJECT = json.loads(Path(__file__).with_name("project.json").read_text())["project"]


def github(path, method="GET"):
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "php-private-staging"}
    if token:
        headers["Authorization"] = "Bearer " + token
    for attempt in range(4):
        try:
            with urlopen(Request("https://api.github.com/" + path, headers=headers, method=method), timeout=60) as response:
                return json.loads(response.read() or b"null")
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2**attempt)


def ident():
    return build_id(os.environ["PRIVATE_BUILD_ID"])


def base():
    return prefix(PROJECT, ident())


def read_plan(store):
    return validate_plan(store.get_json(base() + "/plan.json"), PROJECT, ident())


def descriptor(file):
    return {"name": Path(file).name, **fingerprint(file)}


def upstream(store, plan=None):
    upstream_id = plan["builder_id"] if plan else build_id(os.environ["PHP_BUILDER_BUILD_ID"])
    record = store.get_json(prefix("php-builder", upstream_id) + "/ready.json")
    if plan:
        require(digest(record) == plan["builder_ready_sha256"], "Builder approval changed")
    # Branch validation is allowed only in branch staging, never in production.
    payload = verify_ready(record, "php-builder", upstream_id, os.environ["PHP_BUILDER_PRIVATE_SIGNING_KEY"],
                           allow_branch=(plan["ref"] if plan else os.environ["GITHUB_REF"]) != "refs/heads/main")
    return record, payload


def plan_build(store):
    minor = os.environ["PHP_VERSION"]
    require(re.fullmatch(r"[0-9]+\.[0-9]+", minor), "Invalid PHP minor")
    require(os.environ["GITHUB_REPOSITORY"] == "shivammathur/" + PROJECT, "Unexpected repository")
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()) if os.environ.get("GITHUB_EVENT_PATH") else {}
    inputs = event.get("inputs") or {}
    containers = (inputs.get("containers") or os.environ.get("PRIVATE_CONTAINERS") or " ".join(CONTAINERS if PROJECT == "php-builder" else CONTAINERS[:6])).split()
    plan = {"schema": 1, "project": PROJECT, "repository": "shivammathur/" + PROJECT, "id": ident(),
            "revision": os.environ["GITHUB_SHA"], "ref": os.environ["GITHUB_REF"], "php_version": minor,
            "containers": containers, **matrices(PROJECT, containers)}
    if PROJECT == "php-builder":
        require(Path("config/definitions", minor).is_file(), "Unsupported PHP minor")
        name = inputs.get("source-file") or os.environ.get("SOURCE_FILE")
        if not name:
            matches = [k.removeprefix("uploads/") for k in store.list("uploads/") if re.fullmatch(r"uploads/php-" + re.escape(minor) + r"\.[0-9]+\.tar\.(gz|xz)", k)]
            require(len(matches) == 1, "Select exactly one source archive for this minor")
            name = matches[0]
        source = source_name(name, minor)
        archive = workdir() / name
        store.get("uploads/" + name, archive)
        source.update(validate_source(archive, source))
        expected = inputs.get("source-sha256") or os.environ.get("SOURCE_SHA256")
        require(not expected or expected == source["sha256"], "Uploaded source checksum mismatch")
        store.put(base() + "/inputs/" + name, archive)
        plan["source"] = source
        plan["php_build_commit"] = github("repos/shivammathur/php-build/commits/debian")["sha"]
    else:
        approval, builder = upstream(store)
        require(builder["plan"]["php_version"] == minor, "Builder PHP minor differs")
        require(set(containers) <= set(builder["plan"]["containers"]), "Builder did not test every selected Ubuntu platform")
        plan.update(source=builder["plan"]["source"], builder_id=builder["plan"]["id"], builder_ready_sha256=digest(approval))
    installer = Path("scripts/install.sh")
    plan["installer"] = descriptor(installer)
    validate_plan(plan, PROJECT, ident())
    store.put(base() + "/inputs/install.sh", installer)
    store.put_json(base() + "/plan.json", plan)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for kind in ("sapis", "packages"):
            output.write(kind + "=" + json.dumps({"include": plan[kind]}, separators=(",", ":")) + "\n")
        for kind in ("container", "host"):
            output.write("tests_" + kind + "=" + json.dumps({"include": [t for t in plan["tests"] if t["kind"] == kind]}, separators=(",", ":")) + "\n")
            output.write("has_" + kind + "=" + str(any(t["kind"] == kind for t in plan["tests"])).lower() + "\n")


def result_key(kind, item):
    return base() + "/results/" + kind + "-" + item["id"] + ".json"


def download_files(store, start, record, directory, selected=None):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    files = [f for f in record["files"] if selected is None or f["name"] in selected]
    require(selected is None or {f["name"] for f in files} == set(selected), "Required archive is absent")
    def fetch(file):
        store.get(start + "/packages/" + record["id"] + "/" + file["name"], directory / file["name"],
                  {k: file[k] for k in ("sha256", "bytes")})
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(fetch, files))


def selected_archive(plan, item):
    return next(name for name in filenames(plan, item) if name.endswith(".zst") and ("-dbgsym" in name) == (item["mode"] == "debug"))


def job(store, phase):
    plan = read_plan(store)
    kind = {"sapi": "sapis", "package": "packages", "test": "tests"}[phase]
    item = next((i for i in plan[kind] if i["id"] == os.environ["PRIVATE_JOB_ID"]), None)
    require(item is not None, "Unexpected private matrix job")
    env = {**os.environ, "PHP_VERSION": plan["php_version"], "BUILD": item["ts"], "TS": item["ts"],
           "BUILDS": item.get("mode", "release"), "SAPI_LIST": " ".join(SAPIS), "SAPI": item.get("sapi", ""),
           "PHP_PRIVATE_RELEASE_VERSION": plan["source"]["version"], "PRIVATE_WORK": str(workdir()),
           "GITHUB_MESSAGE": "--build-all skip-release", "PHP_SOURCE": "--private", "CONTAINER": item["container"],
           "PRIVATE_TEST_KIND": item.get("kind", ""), "PRIVATE_TEST_OS": item["os"], "NIGHTLY": "false"}
    package_record = None
    if phase == "sapi":
        archive = workdir() / plan["source"]["name"]
        store.get(base() + "/inputs/" + archive.name, archive, {k: plan["source"][k] for k in ("sha256", "bytes")})
        validate_source(archive, plan["source"])
        env.update(PHP_PRIVATE_SOURCE_ARCHIVE=str(archive), PHP_PRIVATE_SOURCE_SHA256=plan["source"]["sha256"],
                   PHP_PRIVATE_BUILD_COMMIT=plan["php_build_commit"], PHP_BUILD_TMPDIR=str(workdir() / "php-build"))
    elif phase == "package" and PROJECT == "php-builder":
        for sapi in plan["sapis"]:
            if sapi["container"] == item["container"] and sapi["ts"] == item["ts"]:
                record = store.get_json(result_key("sapis", sapi))
                validate_result(record, plan, sapi, "sapis")
                file = record["files"][0]
                require(len(record["files"]) == 1 and file["name"] == sapi_filename(plan, sapi), "Invalid SAPI archive")
                download_files(store, base(), record, workdir() / "sapis")
    elif phase == "package":
        _, builder = upstream(store, plan)
        bp = builder["plan"]
        package = package_for_test(bp, item)
        record = next(r for r in builder["packages"] if r["id"] == package["id"])
        directory = workdir() / "builder"
        download_files(store, prefix("php-builder", bp["id"]), record, directory, [selected_archive(bp, item)])
        store.get(prefix("php-builder", bp["id"]) + "/inputs/install.sh", directory / "install.sh", {k: bp["installer"][k] for k in ("sha256", "bytes")})
        env["PHP_BUILDER_ARCHIVE_DIR"] = str(directory)
    elif phase == "test":
        package = package_for_test(plan, item)
        package_record = validate_result(store.get_json(result_key("packages", package)), plan, package, "packages")
        directory = workdir() / "packages"
        selected = selected_archive(plan, item) if PROJECT == "php-builder" else filenames(plan, item)[0]
        download_files(store, base(), package_record, directory, [selected])
        store.get(base() + "/inputs/install.sh", directory / "install.sh", {k: plan["installer"][k] for k in ("sha256", "bytes")})
        env["PHP_BUILDER_ARCHIVE_DIR" if PROJECT == "php-builder" else "PHP_UBUNTU_ARCHIVE_DIR"] = str(directory)
    subprocess.run(["bash", "scripts/private/job.sh", phase], env=env, check=True)
    record = {"id": item["id"], "plan_sha256": digest(plan), "status": "success"}
    if phase == "test":
        record["package_sha256"] = digest(package_record)
    else:
        files = [Path("/tmp/debian", sapi_filename(plan, item))] if phase == "sapi" else [Path("/tmp" if PROJECT == "php-builder" else "builds", name) for name in filenames(plan, item)]
        record["files"] = [descriptor(file) for file in files]
        for file in files:
            store.put(base() + "/packages/" + item["id"] + "/" + file.name, file)
    validate_result(record, plan, item, kind)
    store.put_json(result_key(kind, item), record)


def sapi_filename(plan, item):
    ts = "-zts" if item["ts"] == "zts" else ""
    arch = "_arm64" if item["arch"] == "arm64" else ""
    return f'php_{plan["php_version"]}{ts}-{item["sapi"]}+{item["dist"]}{item["version"]}{arch}.tar.zst'


def approve(store):
    plan = read_plan(store)
    payload = {"plan": plan}
    for kind in ("packages", "tests"):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            payload[kind] = list(pool.map(lambda item: store.get_json(result_key(kind, item)), plan[kind]))
    record = {"payload": payload, "signature": sign(payload, os.environ["PRIVATE_RELEASE_SIGNING_KEY"])}
    verify_ready(record, PROJECT, ident(), os.environ["PRIVATE_RELEASE_SIGNING_KEY"], allow_branch=True)
    store.put_json(base() + "/ready.json", record)


def release(store):
    require(os.environ["GITHUB_REF"] == "refs/heads/main", "Release must run on main")
    payload = verify_ready(store.get_json(base() + "/ready.json"), PROJECT, ident(), os.environ["PRIVATE_RELEASE_SIGNING_KEY"])
    plan = payload["plan"]
    require(plan["php_version"] == os.environ["PHP_VERSION"] and plan["source"]["version"] == os.environ["RELEASE_VERSION"] and plan["source"]["sha256"] == os.environ["SOURCE_SHA256"], "Release inputs differ from approved source")
    official = workdir() / "official-source"
    subprocess.run(["curl", "--disable", "--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https", "--retry", "2", "--connect-timeout", "20", "--max-time", "300", "--output", str(official), plan["source"]["url"]], check=True)
    require(fingerprint(official) == {k: plan["source"][k] for k in ("sha256", "bytes")}, "Announced source differs from staged candidate")
    for record in payload["packages"]:
        download_files(store, base(), record, Path("builds") / record["id"])
    # Publish the installer whose exact bytes were tested with these packages.
    store.get(base() + "/inputs/install.sh", "scripts/install.sh", {k: plan["installer"][k] for k in ("sha256", "bytes")})


def cleanup(store):
    run_id, attempt = ident().split("-")
    repo = "shivammathur/" + PROJECT
    api = f"repos/{repo}/actions/runs/{run_id}"
    run = github(api)
    require(run["status"] == "completed" and run["path"] == ".github/workflows/stage-private.yml" and
            run["head_repository"]["full_name"] == repo and run["run_attempt"] == int(attempt), "Untrusted or unfinished workflow")
    jobs, page = [], 1
    while True:
        response = github(api + f"/attempts/{attempt}/jobs?per_page=100&page={page}")
        jobs += response["jobs"]
        if len(jobs) >= response["total_count"]:
            break
        page += 1
    store.put_json(base() + "/workflow.json", {"run": run, "jobs": jobs})
    if run["conclusion"] == "success":
        payload = verify_ready(store.get_json(base() + "/ready.json"), PROJECT, ident(), os.environ["PRIVATE_RELEASE_SIGNING_KEY"], allow_branch=True)
        require(payload["plan"]["revision"] == run["head_sha"], "Workflow revision differs from approval")
    github(api, "DELETE")


if __name__ == "__main__":
    operation = sys.argv[1]
    store = Store()
    if operation in ("sapi", "package", "test"):
        job(store, operation)
    else:
        {"plan": plan_build, "approve": approve, "release": release, "cleanup": cleanup}[operation](store)
