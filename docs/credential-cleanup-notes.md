# Credential Manager cleanup – what each thing is

## OneDrive – "Microsoft OneDrive Generic Data - Personal Vault VHD Info"

Stores info Windows uses for **OneDrive Personal Vault** (encrypted area in OneDrive). If you don’t use OneDrive or Personal Vault, this is safe to remove. Deleting it only removes the stored credential; it doesn’t uninstall OneDrive. You may get a sign-in prompt if something (e.g. Explorer) tries to use OneDrive later.

---

## virtualapp/didlogical (WindowsLive)

**What it is:** Microsoft’s own credential for Windows Live / identity services (e.g. Outlook.com, Hotmail, Store, “Sign in with Microsoft”). The user value `02uuaqylcjpnrfde` is a normal Microsoft device/account ID, not a random name.

**Safe to delete?** Yes. It may be recreated if you use Microsoft account sign-in or Store. Deleting it is not dangerous; some people remove it to reduce clutter.

---

## JianyingPro Cached Credential

**What it is:** Leftover from **Jianying Pro** (CapCut’s desktop video editor by ByteDance). Appears if you ever installed CapCut/Jianying on this PC.

**Safe to delete?** Yes. If you don’t use that app, removing it only clears cached login/session data.

---

## What the script removes

- **EmbarkID/embark-discovery/discovery-live** – Embark Studios game launcher (THE FINALS, etc.). Safe to remove if you don’t use their games or launcher.
- NordPass, Adobe, Xbox Live (XblGrts), Minecraft/Mojang (MCLMS), OneDrive, virtualapp/didlogical, JianyingPro – see sections above.

---

## What to keep

- **git:https://github.com** (and any other `git:https://...`) – needed for Git over HTTPS.
- **GitHub - huggingface.co/...** – used when you link GitHub to Hugging Face (e.g. HF login or API). Keep if you use Hugging Face; safe to delete if you don’t.
- **vscode-cli-0.vscode-cli** – used by VS Code/Cursor when you run `code .` or `cursor .` from a terminal. Safe to delete; you’ll be prompted again next time the CLI needs auth.
- **MicrosoftAccount:user=...** and **MicrosoftAccount:target=SSO_*** – used for Windows sign-in and Store. Removing them can break “Sign in with Microsoft” or Store until you sign in again. Only remove if you’re sure you don’t rely on a Microsoft account on this PC.

---

## After cleanup

If Git over HTTPS stops working, run `git credential reject` then the next `git` command that needs auth; when prompted, sign in again (or use SSH).
If you later need a removed credential (e.g. OneDrive, Store), the app will just ask you to sign in again.
