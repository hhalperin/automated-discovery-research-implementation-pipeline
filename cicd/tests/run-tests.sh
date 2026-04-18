#!/usr/bin/env bash
# cicd/tests/run-tests.sh — exhaustive end-to-end tests for the CICD module.
# Creates throwaway git repos under $TMPDIR, runs gates, judges, installer,
# and new-repo scaffold. Fails loudly on any regression.

set -euo pipefail

CICD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CICD_ROOT

# Tests create their own throwaway repos, so any CICD_* env vars inherited
# from a parent invocation (e.g., when `cicd run` is itself the test hook
# in CI) must be scrubbed — otherwise the inner repos try to resolve SHAs
# and PR-body files that only exist in the parent repo, causing
# "Invalid revision range" errors and silently-passing should-fail tests.
unset CICD_BASE_SHA CICD_HEAD_SHA CICD_BASE_REF CICD_BRANCH \
      CICD_PR_BODY_FILE CICD_REPO CICD_OUT CICD_CONFIG OPENAI_API_KEY

pass=0; fail=0; failures=()
ok()   { printf '  \e[32mok\e[0m  %s\n' "$*"; pass=$((pass+1)); }
ng()   { printf '  \e[31mFAIL\e[0m %s\n' "$*"; fail=$((fail+1)); failures+=("$*"); }
step() { printf '\n== %s ==\n' "$*"; }

assert_eq() { [[ "$1" == "$2" ]] && ok "$3 ($1)" || ng "$3 (got '$1' expected '$2')"; }

# Isolated work area.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git_init_repo() {
    local dir="$1"
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q -b main
        git config user.email "cicd-test@example.com"
        git config user.name  "cicd-test"
        echo "# seed" > README.md
        mkdir -p src docs
        echo "def hi(): return 1" > src/mod.py
        echo "initial docs" > docs/README.md
        git add .
        git commit -q -m "seed"
        git branch -M main
        # fake origin that points at ourselves so CICD_BASE_REF resolves.
        git remote add origin "$dir"
        git update-ref refs/remotes/origin/main refs/heads/main
    )
}

run_cicd() {
    # Run a CICD subcommand inside $1 with $2+ args, capturing exit code.
    local dir="$1"; shift
    ( cd "$dir" && "$CICD_ROOT/bin/cicd" "$@" )
}

step "installer copies CICD into a fresh repo"
REPO1="$WORK/repo1"
git_init_repo "$REPO1"
"$CICD_ROOT/install.sh" "$REPO1" --quiet
[[ -x "$REPO1/cicd/bin/cicd" ]]            && ok "cicd CLI installed"                       || ng "cicd CLI missing"
[[ -f "$REPO1/.github/workflows/cicd.yml" ]] && ok "caller workflow installed"               || ng "caller workflow missing"
[[ -f "$REPO1/.cicd/config.yaml" ]]        && ok "config installed"                          || ng "config missing"
grep -q '^\.cicd/out/' "$REPO1/.gitignore" && ok ".cicd/out added to .gitignore"             || ng ".gitignore not updated"

step "branch-naming check: pass on 'cursor/feature-x'"
BRANCH_REPO="$WORK/branch-repo"
git_init_repo "$BRANCH_REPO"
"$CICD_ROOT/install.sh" "$BRANCH_REPO" --quiet
(
    cd "$BRANCH_REPO"
    git checkout -q -b cursor/feature-x
    CICD_BRANCH=cursor/feature-x "$CICD_ROOT/bin/cicd" check branch-naming >/dev/null
) && ok "branch-naming pass" || ng "branch-naming pass"

step "branch-naming check: fail on 'hack_thing'"
(
    cd "$BRANCH_REPO"
    git checkout -q -b "hack_thing" 2>/dev/null || git checkout -q hack_thing
    CICD_BRANCH=hack_thing "$CICD_ROOT/bin/cicd" check branch-naming >/dev/null
) && ng "branch-naming should fail" || ok "branch-naming fail"

step "size-cap check: fail when over limit"
SIZE_REPO="$WORK/size-repo"
git_init_repo "$SIZE_REPO"
"$CICD_ROOT/install.sh" "$SIZE_REPO" --quiet
(
    cd "$SIZE_REPO"
    # Tighten cap so we can overshoot easily.
    cat > .cicd/config.yaml <<'YAML'
checks:
  size_cap:
    max_changed_lines: 5
    max_changed_files: 2
YAML
    git checkout -q -b cursor/too-big
    for i in 1 2 3 4; do seq 1 50 > "file${i}.txt"; done
    git add . && git commit -q -m "huge diff"
    CICD_BASE_REF=origin/main "$CICD_ROOT/bin/cicd" check size-cap >/dev/null
) && ng "size-cap should fail" || ok "size-cap fails on too-large diff"

step "doc-parity check: fail when only code changed"
DOC_REPO="$WORK/doc-repo"
git_init_repo "$DOC_REPO"
"$CICD_ROOT/install.sh" "$DOC_REPO" --quiet
(
    cd "$DOC_REPO"
    git checkout -q -b cursor/code-only
    echo "def new(): return 2" >> src/mod.py
    git add src/mod.py && git commit -q -m "code only"
    : > /tmp/empty_body
    CICD_BASE_REF=origin/main CICD_PR_BODY_FILE=/tmp/empty_body \
        "$CICD_ROOT/bin/cicd" check doc-parity >/dev/null
) && ng "doc-parity should fail" || ok "doc-parity fails when only code changed"

step "doc-parity check: pass when docs touched too"
(
    cd "$DOC_REPO"
    echo "- new thing" >> docs/README.md
    git add docs/README.md && git commit -q -m "docs"
    : > /tmp/empty_body
    CICD_BASE_REF=origin/main CICD_PR_BODY_FILE=/tmp/empty_body \
        "$CICD_ROOT/bin/cicd" check doc-parity >/dev/null
) && ok "doc-parity passes when docs updated too" || ng "doc-parity should pass with docs"

step "doc-parity check: docs-skip directive"
DOC_REPO2="$WORK/doc-repo2"
git_init_repo "$DOC_REPO2"
"$CICD_ROOT/install.sh" "$DOC_REPO2" --quiet
(
    cd "$DOC_REPO2"
    git checkout -q -b cursor/skip-docs
    echo "def new(): return 3" >> src/mod.py
    git add . && git commit -q -m "code only"
    printf 'cicd: docs-skip purely internal refactor\n' > /tmp/pr_body
    CICD_BASE_REF=origin/main CICD_PR_BODY_FILE=/tmp/pr_body \
        "$CICD_ROOT/bin/cicd" check doc-parity >/dev/null
) && ok "docs-skip directive passes" || ng "docs-skip should pass"

step "secrets check: fail on AKIA key"
SEC_REPO="$WORK/sec-repo"
git_init_repo "$SEC_REPO"
"$CICD_ROOT/install.sh" "$SEC_REPO" --quiet
(
    cd "$SEC_REPO"
    git checkout -q -b cursor/leak
    echo 'AWS_KEY = "AKIAIOSFODNN7EXAMPLE"' > src/leak.py
    git add . && git commit -q -m "leak"
    CICD_BASE_REF=origin/main "$CICD_ROOT/bin/cicd" check secrets >/dev/null 2>&1
) && ng "secrets should fail on AKIA" || ok "secrets detects AKIA token"

step "revertability check: fail when mixing source + lockfile"
REV_REPO="$WORK/rev-repo"
git_init_repo "$REV_REPO"
"$CICD_ROOT/install.sh" "$REV_REPO" --quiet
(
    cd "$REV_REPO"
    git checkout -q -b cursor/mixed
    echo "lock-dep" > package-lock.json
    echo "def thing(): return 4" >> src/mod.py
    git add . && git commit -q -m "mix"
    : > /tmp/empty_body
    CICD_BASE_REF=origin/main CICD_PR_BODY_FILE=/tmp/empty_body \
        "$CICD_ROOT/bin/cicd" check revertability >/dev/null
) && ng "revertability should fail" || ok "revertability fails on source+lock mix"

step "revertability: allow-mixed override passes"
(
    cd "$REV_REPO"
    printf 'cicd: allow-mixed dep bump for CVE\n' > /tmp/pr_body
    CICD_BASE_REF=origin/main CICD_PR_BODY_FILE=/tmp/pr_body \
        "$CICD_ROOT/bin/cicd" check revertability >/dev/null
) && ok "allow-mixed override passes" || ng "allow-mixed override should pass"

step "install-agent --check returns 1 when Cursor CLI absent"
( unset CURSOR_API_KEY
  PATH=/usr/local/bin:/usr/bin:/bin HOME=$(mktemp -d) "$CICD_ROOT/bin/cicd" install-agent --check --quiet >/dev/null 2>&1
) && ng "install-agent --check should fail without CLI" || ok "install-agent --check fails when CLI absent"

step "judge backend prefers 'agent' over legacy 'cursor-agent'"
( fake_dir=$(mktemp -d)
  cat > "$fake_dir/agent" <<'STUB'
#!/usr/bin/env bash
echo "agent 99.0.0"
STUB
  chmod +x "$fake_dir/agent"
  out=$(PATH="$fake_dir:$PATH" CURSOR_API_KEY=dummy bash -c '. "$CICD_ROOT/lib/common.sh"; . "$CICD_ROOT/lib/judges/_runner.sh"; cicd::judge::_backend')
  rm -rf "$fake_dir"
  [[ "$out" == "cursor-agent" ]]
) && ok "backend resolves to cursor-agent when 'agent' is on PATH" || ng "backend did not detect 'agent' binary"

step "judge with no backend emits 'skipped' verdict"
JUDGE_REPO="$WORK/judge-repo"
git_init_repo "$JUDGE_REPO"
"$CICD_ROOT/install.sh" "$JUDGE_REPO" --quiet
(
    cd "$JUDGE_REPO"
    git checkout -q -b cursor/tiny
    echo "def tiny(): return 5" >> src/mod.py
    echo "- tiny change" >> docs/README.md
    git add . && git commit -q -m "tiny"
    unset OPENAI_API_KEY
    : > /tmp/empty_body
    CICD_BASE_REF=origin/main CICD_PR_BODY_FILE=/tmp/empty_body \
        "$CICD_ROOT/bin/cicd" judge improvement >/dev/null
    status=$(jq -r '.status' .cicd/out/judges/improvement.json)
    verdict=$(jq -r '.details.verdict' .cicd/out/judges/improvement.json)
    [[ "$status" == "skipped" && "$verdict" == "skipped" ]]
) && ok "judge skipped without backend" || ng "judge should be skipped"

step "full 'cicd run' produces report.md and labels.txt"
FULL_REPO="$WORK/full-repo"
git_init_repo "$FULL_REPO"
"$CICD_ROOT/install.sh" "$FULL_REPO" --quiet
(
    cd "$FULL_REPO"
    git checkout -q -b cursor/full-run
    echo "def full(): return 6" >> src/mod.py
    echo "- full run note" >> docs/README.md
    git add . && git commit -q -m "full run"
    : > /tmp/empty_body
    CICD_BASE_REF=origin/main CICD_PR_BODY_FILE=/tmp/empty_body \
        "$CICD_ROOT/bin/cicd" run >/dev/null
    [[ -f .cicd/out/report.md ]]
    [[ -f .cicd/out/labels.txt ]]
    [[ -f .cicd/out/summary.json ]]
    grep -q 'CICD' .cicd/out/report.md
    jq -e '.gate_status' .cicd/out/summary.json >/dev/null
) && ok "full run produces expected artifacts" || ng "full run artifacts missing"

step "new-repo scaffolder produces a working python project"
SCAFFOLD_OUT="$WORK/scaffold"
"$CICD_ROOT/bin/cicd" new-repo demo-service \
    --language python --owner demo-org --path "$SCAFFOLD_OUT/demo-service" --no-git >/dev/null
[[ -f "$SCAFFOLD_OUT/demo-service/pyproject.toml" ]]                          && ok "pyproject.toml present"          || ng "pyproject.toml missing"
if [[ -f "$SCAFFOLD_OUT/demo-service/src/demo_service/__init__.py" ]]; then
    ok "package directory renamed from placeholder"
else
    ng "package directory renamed from placeholder (not found)"
fi
[[ -f "$SCAFFOLD_OUT/demo-service/.github/workflows/cicd.yml" ]]              && ok "caller workflow vendored"        || ng "caller workflow missing in scaffold"
[[ -f "$SCAFFOLD_OUT/demo-service/cicd/bin/cicd" ]]                           && ok "cicd CLI vendored"               || ng "cicd CLI missing in scaffold"
grep -q 'name = "demo-service"' "$SCAFFOLD_OUT/demo-service/pyproject.toml"   && ok "pyproject has new name"          || ng "pyproject name not substituted"

step "new-repo scaffolder: generic language"
"$CICD_ROOT/bin/cicd" new-repo generic-thing --language generic --owner demo-org \
    --path "$SCAFFOLD_OUT/generic-thing" --no-git >/dev/null
[[ -f "$SCAFFOLD_OUT/generic-thing/.cicd/config.yaml" ]] && ok "generic scaffold installed config" || ng "generic scaffold config missing"

echo
echo "==== summary ===="
echo "passed: $pass"
echo "failed: $fail"
if (( fail > 0 )); then
    printf '  * %s\n' "${failures[@]}"
    exit 1
fi
exit 0
