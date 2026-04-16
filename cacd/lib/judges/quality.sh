#!/usr/bin/env bash
# Judge: code-quality rubric (style, testing, complexity).
set -euo pipefail
. "$CACD_ROOT/lib/common.sh"
. "$CACD_ROOT/lib/judges/_runner.sh"

prompt="$CACD_ROOT/prompts/quality.md"
cacd::judge::run quality "$prompt"
