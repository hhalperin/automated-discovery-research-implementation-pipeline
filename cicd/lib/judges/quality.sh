#!/usr/bin/env bash
# Judge: code-quality rubric (style, testing, complexity).
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"
. "$CICD_ROOT/lib/judges/_runner.sh"

prompt="$CICD_ROOT/prompts/quality.md"
cicd::judge::run quality "$prompt"
