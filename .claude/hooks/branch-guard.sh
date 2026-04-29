#!/bin/bash
# .claude/hooks/branch-guard.sh
# Claude Code PreToolUse hook for Bash commands.
# Exit 0 = allow, Exit 2 = block with feedback to Claude.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

PROTECTED="main develop release hotfix"

# Block direct checkout to protected branches
for branch in $PROTECTED; do
  if echo "$COMMAND" | grep -qE "git (checkout|switch)\s+${branch}(\s|$)"; then
    echo "BLOCKED: Direct checkout to '${branch}'. Create a feature branch: git checkout -b feature/your-change ${branch}" >&2
    exit 2
  fi
done

# Block force push
if echo "$COMMAND" | grep -qE "git push.*(--force|-f\b)"; then
  echo "BLOCKED: Force push prohibited. Use --force-with-lease only if absolutely necessary." >&2
  exit 2
fi

# Block hard reset
if echo "$COMMAND" | grep -qE "git reset --hard"; then
  echo "BLOCKED: git reset --hard is dangerous. Use git stash or git reset --soft." >&2
  exit 2
fi

# Block deletion of protected branches
for branch in $PROTECTED; do
  if echo "$COMMAND" | grep -qE "git branch\s+-[dD]\s+${branch}"; then
    echo "BLOCKED: Cannot delete protected branch '${branch}'." >&2
    exit 2
  fi
done

# Block direct push to main/develop
if echo "$COMMAND" | grep -qE "git push\s+(origin\s+)?(main|develop)(\s|$)"; then
  echo "BLOCKED: Direct push to protected branch. Open a PR to develop instead." >&2
  exit 2
fi

exit 0
