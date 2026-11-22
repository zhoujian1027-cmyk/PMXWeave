#!/bin/sh
HERE=$(cd "$(dirname "$0")" && pwd)
exec sh "$HERE/run_regression.sh" er "$@"
