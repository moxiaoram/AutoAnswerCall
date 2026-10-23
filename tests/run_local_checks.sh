#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BIN="${TMPDIR:-/tmp}/clashassist-battle-test-$$"
trap 'rm -f "$BIN"' EXIT
cd "$ROOT"
cc -std=c11 -Wall -Wextra -Werror -I. tests/battle_core.c -o "$BIN"
"$BIN"
python3 tests/verify_diagnostics.py
python3 -m unittest discover -s tests -p 'test_*.py' -v
