#!/bin/sh
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { echo "PEEK_FAIL usage: sh analyses_template/tools/data_peek.sh <analysis>/<data>.csv" >&2; exit 2; }
[ -f "$1" ] || { echo "PEEK_FAIL missing file: $1" >&2; exit 2; }
exec node "$SELF/data_peek.mjs" "$@"
