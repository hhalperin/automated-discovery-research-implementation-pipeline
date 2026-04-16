#!/usr/bin/env bash
# Judge: is this change a net improvement over the baseline?
set -euo pipefail
. "$CACD_ROOT/lib/common.sh"
. "$CACD_ROOT/lib/judges/_runner.sh"

prompt="$CACD_ROOT/prompts/improvement.md"
cacd::judge::run improvement "$prompt"
