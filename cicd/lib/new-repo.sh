#!/usr/bin/env bash
# cicd/lib/new-repo.sh — scaffold a brand-new repo with CICD preinstalled.
#
# Usage:
#   cicd new-repo <name> [--language py|node|generic] [--owner <gh-owner>]
#                        [--path <dir>] [--no-git] [--no-remote]
#
# Produces a git-initialized directory with:
#   * language-appropriate starter layout (src/, tests/, docs/)
#   * CICD installed (.github/workflows/cicd*.yml, .cicd/config.yaml, cicd/)
#   * PR template, CODEOWNERS, CONTRIBUTING.md, README, LICENSE stub
#   * an initial commit on `main`
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

name="${1:?repo name required}"; shift || true
language="generic"
owner=""
target_dir=""
no_git=0
no_remote=1   # default: do not create remote automatically

while [[ $# -gt 0 ]]; do
    case "$1" in
        --language) language="$2"; shift ;;
        --language=*) language="${1#*=}" ;;
        --owner) owner="$2"; shift ;;
        --owner=*) owner="${1#*=}" ;;
        --path) target_dir="$2"; shift ;;
        --path=*) target_dir="${1#*=}" ;;
        --no-git) no_git=1 ;;
        --create-remote) no_remote=0 ;;
        *) cicd::err "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

case "$language" in python|py|node|js|ts|generic) ;; *)
    cicd::err "unsupported language: $language (use py|node|generic)"
    exit 2
    ;;
esac

target_dir="${target_dir:-$PWD/$name}"
mkdir -p "$target_dir"

cp -r "$CICD_ROOT/templates/new-repo/common/." "$target_dir/"
if [[ -d "$CICD_ROOT/templates/new-repo/$language" ]]; then
    cp -r "$CICD_ROOT/templates/new-repo/$language/." "$target_dir/"
fi

# Substitute placeholders in file contents and path names.
python3 - "$target_dir" "$name" "$owner" "$language" <<'PY'
import pathlib, sys
root, name, owner, language = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
pkg_name = name.replace("-", "_").replace(".", "_")
subs_content = {
    "{{REPO_NAME}}": name,
    "{{PACKAGE_NAME}}": pkg_name,
    "{{OWNER}}": owner or "your-org",
    "{{LANGUAGE}}": language,
}
# Path substitutions: package-name path segments should use underscore form
# so Python imports work.
subs_paths = {
    "{{REPO_NAME}}": pkg_name,
    "{{PACKAGE_NAME}}": pkg_name,
    "{{OWNER}}": owner or "your-org",
    "{{LANGUAGE}}": language,
}
subs = subs_content
root_path = pathlib.Path(root)
for p in root_path.rglob("*"):
    if not p.is_file():
        continue
    try:
        text = p.read_text()
    except Exception:
        continue
    new = text
    for k, v in subs.items():
        new = new.replace(k, v)
    if new != text:
        p.write_text(new)
# Rename any path segments carrying placeholders (deepest first).
for p in sorted(root_path.rglob("*"), key=lambda x: -len(str(x))):
    new_name = p.name
    for k, v in subs_paths.items():
        new_name = new_name.replace(k, v)
    if new_name != p.name:
        p.rename(p.with_name(new_name))
PY

# Install CICD into the new repo.
"$CICD_ROOT/install.sh" "$target_dir" --quiet

if (( no_git == 0 )); then
    (
        cd "$target_dir"
        if [[ ! -d .git ]]; then
            git init -q -b main
            git add .
            git commit -q -m "chore: scaffold $name with CICD" || true
        fi
        if (( no_remote == 0 )) && [[ -n "$owner" ]] && command -v gh >/dev/null 2>&1; then
            gh repo create "$owner/$name" --private --source . --remote origin --push || cicd::err "gh repo create failed"
        fi
    )
fi

cicd::log "scaffolded $language repo at: $target_dir"
