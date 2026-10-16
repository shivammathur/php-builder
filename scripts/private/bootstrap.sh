#!/usr/bin/env bash
set -euo pipefail
# This bootstrap handles public tooling only, before private source is accessed.
if ! command -v python3 >/dev/null || ! command -v curl >/dev/null; then
  log=$(mktemp)
  if ! (apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y python3 curl ca-certificates) >"$log" 2>&1; then
    echo 'Private tooling bootstrap failed.' >&2
    exit 1
  fi
  rm -f "$log"
fi
