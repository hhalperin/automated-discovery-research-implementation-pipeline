# Installing CACD

## Into an existing repo

From a clone of this repo:

```bash
path/to/cacd/install.sh /path/to/target-repo
```

Or, if you have this repo vendored already, from inside the target:

```bash
./cacd/install.sh .
```

One-liner (public):

```bash
curl -fsSL https://raw.githubusercontent.com/{{OWNER}}/cacd/main/cacd/install.sh | bash
```

The installer is **idempotent**:

- `cacd/` is always refreshed (versioned artifact).
- `.github/workflows/cacd.yml` and `cacd-cleanup.yml` are always
  refreshed.
- `.cacd/config.yaml`, `.cacd/repo-context.md`, the PR template and
  `CODEOWNERS` are **only installed if missing** (so your customizations
  survive upgrades). Pass `--force` to overwrite.

After install:

1. Commit the new files.
2. Set any optional secrets in *GitHub → Settings → Secrets*:
   - `OPENAI_API_KEY` — required to enable LLM judges.
   - `CACD_SCAFFOLD_TOKEN` — for the *CACD New Repo* dispatcher if you
     want it to create remotes in a different org than
     `${{ github.repository_owner }}`.
3. Open a PR. CACD posts a sticky review comment with gate and judge
   results.

## Into a brand-new repo (first-class)

```bash
./cacd/bin/cacd new-repo my-new-service --language python --owner my-org
```

That single command produces a git-initialized repo at
`./my-new-service` with:

- Language-appropriate scaffolding (`pyproject.toml`, starter package,
  `tests/`, etc.).
- CACD installed (`cacd/`, `.github/workflows/cacd*.yml`,
  `.cacd/config.yaml`).
- `README.md`, `CONTRIBUTING.md`, `LICENSE`, `docs/`, PR template.
- An initial commit on `main`.

Languages supported out of the box: `python`, `node`, `generic`. Add
more by dropping a directory into `cacd/templates/new-repo/<lang>/`.

### From GitHub Actions

Keep this repo as an "org template" and dispatch the *CACD New Repo*
workflow with `name`, `owner`, `language`, `visibility` inputs — it
will create and push the new repo for you.

## Requirements on the runner / local machine

- `bash`, `git`, `jq`, `python3` (>=3.11) with `pyyaml`.
- `gh` CLI for branch cleanup and revert helpers.
- Optional: `openai` Python package + `OPENAI_API_KEY` for judges.
