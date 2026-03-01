# Git Credential Manager Setup on Windows

## Step 1: Current State (as of this guide)

| Item | Current state |
|------|----------------|
| **Credential helper** | Git Credential Manager (new GCM) at `C:\Users\harri\AppData\Local\Programs\Git Credential Manager\git-credential-manager.exe` |
| **Default GitHub user** | `hhalperin` (global `credential.https://github.com.username`) |
| **Second account** | `harrison-quant-h2` (path override for `github.com/harrison-quant-h2/...`) |
| **SSH keys** | `~/.ssh/id_ed25519` (hhalperin), `~/.ssh/id_ed25519_quant` (harrison-quant-h2) |
| **SSH config** | `Host github.com` → quant key; `Host halpie` → hhalperin key; `Host quant` → quant key |
| **User-level PAT** | Not set (no `GITHUB_TOKEN` / `GITHUB_PAT` in User env) |

Important: Right now **default** `github.com` in SSH uses the **quant** key (`id_ed25519_quant`). If you want default to be hhalperin when using SSH, you either use the host alias `halpie` in clone URLs, or change the config below.

---

## Step 2: Two Ways to Avoid Authenticating All the Time

### Option A: HTTPS + GCM (store a PAT once)

- Git uses **HTTPS** URLs (`https://github.com/...`).
- GCM stores your credential (OAuth **or** PAT) in Windows Credential Manager and reuses it — no repeated prompts.
- **PAT:** If you use a classic PAT with specific permissions, you can store it once in GCM; after that Git won’t ask again.
- **Same PAT** can be set as a **User** environment variable (`GITHUB_TOKEN` or `GITHUB_PAT`) so GitHub MCP works from your user profile (all workspaces), not per-workspace.

### Option B: SSH (keys only for Git)

- Git uses **SSH** URLs (`git@github.com:...` or `git@halpie:...` / `git@quant:...`).
- Auth is via SSH key; no PAT needed for Git. Once the key is in `ssh-agent` (and added to GitHub), you don’t type anything for Git.
- **PAT still needed for GitHub MCP:** MCP uses the GitHub **API**, not Git. So you’d set a PAT in a **User** env var for MCP only; Git would never use it.

---

## Step 3: Recommended Plan

**Goal:** No repeated Git auth + PAT available at user level for MCP.

- **For Git:** Prefer **SSH** (you already have keys and host aliases). No PAT needed for Git; no “string binding” or GCM popups.
- **For MCP:** Store **one classic PAT** (with the scopes you need) in a **User** environment variable so GitHub MCP works from your profile.

If you’d rather use **HTTPS + PAT for Git** (e.g. you want one PAT for both Git and MCP), use Option A below and the same PAT in User env for MCP.

---

## Step 4: Step-by-Step

### Path A — HTTPS + GCM with PAT (one PAT for Git and MCP)

1. **Ensure GCM is the only credential helper**
   ```bash
   git config --global --unset-all credential.helper
   git config --global credential.helper "C:/Users/harri/AppData/Local/Programs/Git Credential Manager/git-credential-manager.exe"
   ```
2. **Store your PAT in GCM once** (replace with your real PAT; use the account you want as default, e.g. hhalperin):
   ```bash
   git credential approve
   ```
   Then type (or paste) these lines and press Enter twice:
   ```
   protocol=https
   host=github.com
   username=hhalperin
   password=YOUR_CLASSIC_PAT_HERE
   ```
3. **Optional:** To avoid any interactive prompt if something goes wrong:
   ```bash
   git config --global credential.interactive never
   ```
4. **User-level PAT for MCP:** Set a **User** (not System, not workspace) environment variable:
   - Variable: `GITHUB_TOKEN` (or `GITHUB_PAT`, if your MCP config uses that name).
   - Value: same classic PAT (or a second PAT if you want different scopes for API).
   - How: Windows Settings → System → About → Advanced system settings → Environment Variables → User variables → New (or Edit) → set `GITHUB_TOKEN` = your PAT.

After this, Git over HTTPS won’t ask again, and MCP can use the same PAT from your user profile.

---

### Path B — SSH for Git + PAT only for MCP (recommended)

1. **Use SSH URLs for GitHub**
   - Default (hhalperin): clone/push with `git@halpie:hhalperin/REPO.git` or `git@halpie:rolefinder/REPO.git`.
   - Other account: `git@quant:harrison-quant-h2/REPO.git`.
   - If you want `git@github.com:...` to mean hhalperin by default, change `~/.ssh/config` so `Host github.com` uses `id_ed25519` (see below).

2. **Make SSH not ask every time**
   - Your config already has `AddKeysToAgent yes`. Ensure the agent is running and keys are added once:
     ```powershell
     Get-Service ssh-agent | Set-Service -StartupType Manual
     Start-Service ssh-agent
     ssh-add C:\Users\harri\.ssh\id_ed25519
     ssh-add C:\Users\harri\.ssh\id_ed25519_quant
     ```
   - After that, Git over SSH won’t prompt for auth (until keys are removed from the agent or machine restarts, depending on config).

3. **Optional: Default `github.com` to hhalperin in SSH**
   - Edit `~/.ssh/config` so the **first** `Host github.com` block uses hhalperin’s key:
     ```
     Host github.com
       HostName github.com
       User git
       IdentityFile C:/Users/harri/.ssh/id_ed25519
       IdentitiesOnly yes
       AddKeysToAgent yes
     ```
   - Keep `Host halpie` and `Host quant` as they are for explicit account choice.

4. **User-level PAT for MCP only**
   - Set **User** env var `GITHUB_TOKEN` (or whatever MCP expects) to your classic PAT.
   - Git will never use this; it’s only for GitHub MCP from your user profile.

---

## Step 5: Summary

| Goal | Action |
|------|--------|
| No repeated Git auth (HTTPS) | Use GCM; store PAT once with `git credential approve` (Path A). |
| No repeated Git auth (SSH) | Use SSH URLs (`halpie` / `quant` or `github.com`); add keys to `ssh-agent` (Path B). |
| MCP from user profile | Set **User** env var `GITHUB_TOKEN` (or `GITHUB_PAT`) to your classic PAT. |
| Default account = hhalperin | Already set for HTTPS (`credential.https://github.com.username=hhalperin`). For SSH, use `halpie` in URLs or make `Host github.com` use `id_ed25519`. |

If you tell me whether you want Path A (HTTPS + PAT in GCM) or Path B (SSH + PAT only for MCP), I can give you the exact commands to run next (including the one-time PAT store or SSH config edit).
