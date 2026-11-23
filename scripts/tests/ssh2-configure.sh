#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Keep the optional signal feature probe, without weakening required APIs or
# changing already-correct (older or future) configure scripts.
for PHP_VERSION in 7.2 8.5 8.6 8.7; do
  mkdir -p "$work/$PHP_VERSION"
  cd "$work/$PHP_VERSION"
  touch ssh2.c ssh2_fopen_wrappers.c
  cat > config.m4 <<'M4'
  AC_MSG_CHECKING([for libssh2 version >= 1.9.0])
  AC_MSG_ERROR([libssh2 version >= 1.9.0 not found])
  PHP_CHECK_LIBRARY(ssh2,libssh2_session_hostkey,
  [
    AC_DEFINE(HAVE_SSH2LIB,1,[Have libssh2])
  ],[
    AC_MSG_ERROR([libssh2 library not found or too old; version 1.9.0 or newer is required])
  ],[
    -L$SSH2_DIR/lib -lm
  ])
  PHP_CHECK_LIBRARY(ssh2,libssh2_channel_signal_ex,
  [
    AC_DEFINE(PHP_SSH2_CHANNEL_SIGNAL, 1, [Have libssh2 with channel signal support])
  ],[
  ],[
    -L$SSH2_DIR/lib -lm
  ])
M4
  cp config.m4 expected.m4
  # Reproduce ssh2 1.6.0's fatal optional-symbol check.
  sed -i '/AC_DEFINE(PHP_SSH2_CHANNEL_SIGNAL/,+1!b; /\],\[/a\    AC_MSG_ERROR([libssh2_channel_signal_ex not found; ensure the linked libssh2 matches the 1.9.0 or newer headers])' config.m4
  grep -q 'AC_MSG_ERROR(\[libssh2_channel_signal_ex' config.m4

  # shellcheck source=scripts/patch-extensions.sh
  . "$repo/scripts/patch-extensions.sh"
  patch_ssh2
  cmp expected.m4 config.m4
  patch_ssh2
  cmp expected.m4 config.m4
  echo "PHP $PHP_VERSION: optional probe preserved, required checks unchanged, patch idempotent"
done
