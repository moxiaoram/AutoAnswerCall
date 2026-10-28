#!/bin/sh
# This wrapper verifies the *compiled* package on macOS or Linux.
# Only RootHide artifacts are supported for this device-targeted project.
set -eu
if [ "$#" -ne 2 ] || [ "$2" != 'roothide' ]; then
    echo 'Usage: sh tools/verify_deb.sh /path/to/package.deb roothide' >&2
    exit 2
fi
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$SCRIPT_DIR/../scripts/verify_relaxin_deb.py" "$1"
