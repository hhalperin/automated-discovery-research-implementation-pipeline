# Git Credentials — Local Inspection Checklist (Phase 2)

**Purpose:** Audit local state *external to SSH keys* before switching to Path B (SSH for Git, PAT only for MCP). All checks are read-only.

**Source:** Phase 1 research (string binding invalid + multi-account GCM prompts) + `docs/git-credentials-windows-setup.md`.

---

## A. Credential helpers (duplicate / conflicting)

| # | What to check | Exact command or location | Good | Bad |
|---|----------------|---------------------------|------|-----|
| A1 | All `credential.helper` values (system, global, local) | `git config --list --show-origin` then filter for lines containing `credential.helper` | Single helper (GCM exe path or `manager`); no empty; no mix of manager + manager-core + path | Multiple different helpers; empty `credential.helper=`; legacy + new mixed |
| A2 | Whether Git actually invokes one or many helpers | `git config --get-all credential.helper` (global + system merged) | One value, or multiple that are intentional (e.g. cache then manager) | Two conflicting GCMs (e.g. `manager` and full path to different exe) |

---

## B. Windows Credential Manager (stale Git entries)

| # | What to check | Exact command or location | Good | Bad |
|---|----------------|---------------------------|------|-----|
| B1 | Any stored credentials for Git/HTTPS GitHub | `cmdkey /list` — inspect output for targets containing `git:`, `gh:`, or `github` | None (Path B) or only current GCM-written entries | Legacy `LegacyGeneric:target=git:https://github.com` or `gh:github.com:...` that could trigger GCM vault RPC |
| B2 | Count of Git-related entries | Same output; count lines with Target: containing git or gh | 0 for Path B; or small number if keeping HTTPS for some repos | Many old entries (increases chance of vault RPC / "string binding" on read) |

---

## C. GCM / credential config (conflicting or prompt-forcing)

| # | What to check | Exact command or location | Good | Bad |
|---|----------------|---------------------------|------|-----|
| C1 | All global `credential.*` settings | `git config --global --list` then filter for `credential.` | `useHttpPath true`; no `credential.interactive=always` or `force` or `true` | `credential.interactive=always` (or force/true) causing repeated prompts |
| C2 | Per-URL username / path settings | Same; look for `credential.https://github.com.*` | Consistent with doc (e.g. default username hhalperin; path override for harrison-quant-h2) | Conflicting usernames for same path; empty username where path is used |
| C3 | credential.modalprompt | Same | `false` or unset (optional) | `true` if it forces modal and contributes to popups |

---

## D. Environment variables (override credential behavior)

| # | What to check | Exact command or location | Good | Bad |
|---|----------------|---------------------------|------|-----|
| D1 | GIT_CREDENTIAL_* and GCM_* in process env | PowerShell: `Get-ChildItem Env: | Where-Object { $_.Name -match 'GIT_CREDENTIAL|GCM_' }` | None, or GCM_* set to `auto` / desired | `GIT_CREDENTIAL_HELPER` overriding config; `GCM_INTERACTIVE=always` or `force` |
| D2 | GITHUB_TOKEN / GITHUB_PAT (context only) | Same; filter for GITHUB_ | Unset or set for MCP only (no impact on Git if using Path B) | N/A for "bad" — just report present/absent |

---

## E. GCM binary and version (wrong or legacy helper)

| # | What to check | Exact command or location | Good | Bad |
|---|----------------|---------------------------|------|-----|
| E1 | Which `git-credential-manager*.exe` Git would use | From A: value of `credential.helper`. Then check file exists: `Test-Path "<value>"` if path | Path points to `...\Git Credential Manager\git-credential-manager.exe` (new GCM) | Path points to `C:\Program Files\Git\mingw64\bin\git-credential-manager.exe` (legacy) |
| E2 | Presence of legacy GCM in Git install | `Get-ChildItem "C:\Program Files\Git\mingw64\bin" -Filter "*credential*" -ErrorAction SilentlyContinue | Select-Object Name` | New GCM not invoking legacy; legacy binary may exist but not be used | Legacy is the one configured (system or global credential.helper) |
| E3 | PATH / which helper runs | `where.exe git-credential-manager 2>$null` | Only new GCM path, or not in PATH (Git uses config) | Legacy GCM earlier in PATH than new one |

---

## F. System-level Git config (stacked helper)

| # | What to check | Exact command or location | Good | Bad |
|---|----------------|---------------------------|------|-----|
| F1 | System credential.helper | `git config --system --get-all credential.helper` (may need elevated) | Unset or `manager` (and matches desired GCM) | `manager` pointing to legacy; or system helper causing duplicate invocations |
| F2 | Any system credential.* | `git config --system --list 2>$null` filtered for credential | Empty or aligned with global | System credential.interactive=always; conflicting helper |

---

## Output format for Phase 3 executors

For each section (A–F), return:

- **Section:** [A|B|C|D|E|F]
- **Commands run:** (exact commands)
- **Findings:** For each checklist item, one line: "[Item] GOOD | BAD: [reason]"
- **Raw output:** (truncated if very long) so main agent can verify

No changes; inspect only.
