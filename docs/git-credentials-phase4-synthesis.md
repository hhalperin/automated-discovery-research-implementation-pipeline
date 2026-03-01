# Phase 4 — Synthesis: Path B + Cleanup

## Aggregated findings (Phase 3)

| Section | Item | Result | Detail |
|---------|------|--------|--------|
| A | A1, A2 | **BAD** | Two credential helpers: **system** `manager` (resolves to legacy GCM in Git install) + **global** full path (new GCM). Git invokes both. |
| B | B1 | **BAD** | One legacy Windows Credential Manager entry: `LegacyGeneric:target=git:https://github.com/hhalperin/cursor-drive` (User: hhalperin). Can trigger vault RPC / "string binding invalid" when GCM reads the vault. |
| B | B2 | GOOD | Only 2 Git-related entries; not "many." |
| C | C1–C3 | GOOD | useHttpPath true; no credential.interactive=always; modalprompt false; per-URL usernames match doc. |
| D | D1 | GOOD | No GIT_CREDENTIAL_* or GCM_* env vars. |
| D | D2 | (info) | GITHUB_PERSONAL_ACCESS_TOKEN present (for MCP; no impact on Git). |
| E | E1, E3 | GOOD | Global helper points to new GCM exe; git-credential-manager not on PATH. |
| E | E2 | **BAD** | Legacy GCM exe present at `C:\Program Files\Git\mingw64\bin\git-credential-manager.exe`; **system** config uses `manager`, which uses this legacy binary. |
| F | F1, F2 | **BAD** | System `credential.helper=manager` (legacy); stacks with global and causes duplicate/conflicting helper invocations. |

---

## Root cause (aligned with Phase 1 research)

1. **Duplicate/conflicting credential helpers** — System runs **legacy** GCM (`manager` → Git\mingw64\bin), global runs **new** GCM (AppData\…\Git Credential Manager). Git calls both. Legacy GCM uses the RPC path that produces "The string binding is invalid" (GCM #1895, RPC_S_INVALID_STRING_BINDING).
2. **Stale credential in Windows Credential Manager** — `git:https://github.com/hhalperin/cursor-drive` can trigger vault access; combined with legacy GCM, that path can hit the same RPC error.

---

## Is Path B sufficient to resolve the errors?

**Yes.** Path B (SSH for Git, PAT only for MCP) stops Git from using GCM for GitHub. No HTTPS → no credential helper for GitHub → no GCM, no vault RPC, no "string binding invalid" from Git operations.

---

## Is additional cleanup required?

**Yes, recommended** — so that:

- Any future HTTPS use (or other tools that use the same credential store) doesn’t hit the same errors.
- Config is consistent and predictable.

Cleanup does not block Path B; you can switch to SSH first and do cleanup when convenient.

---

## Final ordered action list

1. **Switch to Path B (SSH for Git)**
   - Use SSH URLs for GitHub (`git@halpie:...`, `git@quant:...`, or fix `Host github.com` to use hhalperin key per doc).
   - Add keys to ssh-agent if needed.
   - Set User env `GITHUB_TOKEN` (or keep `GITHUB_PERSONAL_ACCESS_TOKEN`) for MCP only.

2. **Remove duplicate credential helper (system)**
   - Unset system `credential.helper` so only global (new GCM) is used when HTTPS is used:
     `git config --system --unset credential.helper`
   - (Requires elevated prompt.) If you prefer not to touch system config, leave as-is; Path B still avoids the error for Git.

3. **Remove stale Git/HTTPS credentials from Windows Credential Manager**
   - Delete entries that could trigger GCM vault access:
     - `LegacyGeneric:target=git:https://github.com/hhalperin/cursor-drive`
   - Option: run `cmdkey /delete:"LegacyGeneric:target=git:https://github.com/hhalperin/cursor-drive"`.
   - If you use Hugging Face with Git, keep or delete `GitHub - huggingface.co/...` as needed; it’s unrelated to GitHub.com.

4. **(Optional) Simplify global credential config for Path B**
   - If you will use **only** SSH for GitHub: you can unset global `credential.helper` for a purely SSH-based Git experience, or leave it so occasional HTTPS (e.g. other hosts) still uses new GCM. Your choice.

5. **(Optional) Default SSH `github.com` to hhalperin**
   - In `~/.ssh/config`, change the first `Host github.com` block to use `IdentityFile .../id_ed25519` so `git@github.com:...` defaults to hhalperin; keep `halpie` and `quant` for explicit choice.

---

## Summary

| Question | Answer |
|----------|--------|
| Does Path B resolve "string binding invalid"? | **Yes** — SSH bypasses GCM and the RPC path that fails. |
| What was wrong locally? | System credential.helper=manager (legacy GCM) + global GCM path → two helpers; one legacy entry in Windows Credential Manager. |
| Must we clean up before Path B? | No; Path B works without cleanup. Cleanup is recommended so HTTPS/vault use doesn’t hit the same issue later. |
| Order of actions | (1) Path B; (2) unset system credential.helper; (3) delete stale cmdkey entry; (4–5) optional SSH/default and global helper. |
