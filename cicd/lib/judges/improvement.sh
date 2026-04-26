#!/usr/bin/env bash
# Judge: is this change a net improvement over the baseline?
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"
. "$CICD_ROOT/lib/judges/_runner.sh"

prompt="$CICD_ROOT/prompts/improvement.md"
cicd::judge::run improvement "$prompt"
