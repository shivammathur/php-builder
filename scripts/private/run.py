"""Capture all build output, including GitHub workflow commands, into private R2."""
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import traceback

from store import Store, prefix, require, workdir


def main():
    label, *command = sys.argv[1:]
    require(re.fullmatch(r"[a-z0-9_.-]+", label) and command, "Invalid private step")
    log = workdir() / (label + ".log")
    # File commands bypass stdout capture. Keep their data private as well.
    env = dict(os.environ)
    for name in ("GITHUB_STEP_SUMMARY", "GITHUB_ENV", "GITHUB_PATH", "GITHUB_STATE", "GITHUB_OUTPUT"):
        if name == "GITHUB_OUTPUT" and label == "plan":
            continue  # Only the coordinator's validated matrix outputs are public.
        if name in env:
            env[name] = str(workdir() / (label + "-" + name.lower()))
    print("Private operation started; diagnostics are stored in R2.", flush=True)
    with log.open("wb") as output:
        child = subprocess.Popen(command, env=env, stdout=output, stderr=output, start_new_session=True)
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, lambda number, _frame: os.killpg(child.pid, number) if child.poll() is None else None)
        status = child.wait()
        summary = workdir() / (label + "-github_step_summary")
        if summary.is_file():
            output.write(b"\nPrivate step summary:\n")
            with summary.open("rb") as stream:
                shutil.copyfileobj(stream, output)
    try:
        Store().put(prefix(os.environ["PRIVATE_PROJECT"], os.environ["PRIVATE_BUILD_ID"]) + "/logs/" + log.name, log)
        if os.geteuid() == 0 or os.environ.get("GITHUB_ACTIONS") != "true":
            shutil.rmtree(workdir())
        else:
            subprocess.run(["sudo", "-n", "rm", "-rf", "--", str(workdir())], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except Exception:
        # Do not send exception details, URLs or authentication data to Actions.
        with (workdir() / (label + "-transfer.log")).open("w") as output:
            traceback.print_exc(file=output)
        status = 1
    print("Private operation completed." if status == 0 else "Private operation failed; inspect private R2 diagnostics.", flush=True)
    return 0 if status == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        print("Private operation failed before completion.", file=sys.stderr)
        sys.exit(1)
