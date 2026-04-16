#!/usr/bin/env bash
# Judge: do the docs still describe reality after this change?
set -euo pipefail
. "$CACD_ROOT/lib/common.sh"
. "$CACD_ROOT/lib/judges/_runner.sh"

prompt="$CACD_ROOT/prompts/docs-accuracy.md"
cacd::judge::run docs-accuracy "$prompt"
