#!/usr/bin/env bash
# Judge: do the docs still describe reality after this change?
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"
. "$CICD_ROOT/lib/judges/_runner.sh"

prompt="$CICD_ROOT/prompts/docs-accuracy.md"
cicd::judge::run docs-accuracy "$prompt"
