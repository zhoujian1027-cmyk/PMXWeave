#!/bin/sh
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
exec "${NODE:-node}" "$SELF/runtime_paths.mjs" "$@"
