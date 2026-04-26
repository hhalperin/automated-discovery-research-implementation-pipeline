# Scaffolding new repos with CICD

CICD treats "new repos" as a first-class path, so every repo starts out
under the quality loop instead of being retrofitted later.

## CLI

```bash
cicd new-repo <name> [--language py|node|generic] [--owner <gh-owner>]
                     [--path <dir>] [--no-git] [--create-remote]
```

What it does:

1. Copies `cicd/templates/new-repo/common/` into the target directory.
2. Layers `cicd/templates/new-repo/<language>/` on top (if one exists).
3. Substitutes `{{REPO_NAME}}`, `{{OWNER}}`, `{{LANGUAGE}}` in file
   contents **and** file/directory names (so placeholder-named packages
   become the real name).
4. Runs `cicd/install.sh` in the new tree (copies `cicd/` itself +
   workflows + `.cicd/config.yaml`).
5. Initializes git, commits as `chore: scaffold <name> with CICD`.
6. With `--create-remote` (and `gh` authed), pushes to
   `gh:{owner}/{name}` as a private repo.

## GitHub Actions dispatcher

Host this repo as an org template. The `CICD New Repo` workflow
accepts:

| Input | Description | Default |
|-------|-------------|---------|
| `name` | New repo name | — |
| `owner` | `user` or `org` | — |
| `language` | `py`, `node`, `generic` | `generic` |
| `visibility` | `public` or `private` | `private` |

It scaffolds, then creates + pushes the remote via `gh repo create`.

Provide a PAT with repo create scope as `CICD_SCAFFOLD_TOKEN` if the
default `GITHUB_TOKEN` cannot create repos in the target org.

## Adding a language

Create `cicd/templates/new-repo/<lang>/` with any files you want layered
over `common/`. You can include a language-specific
`.cicd/config.yaml` (hooks + anything else). Placeholder tokens work
anywhere.

## Layout produced

```
my-new-service/
├── README.md
├── CONTRIBUTING.md
├── LICENSE
├── .gitignore
├── docs/
│   └── README.md
├── src/my_new_service/__init__.py     # python example
├── tests/test_smoke.py
├── pyproject.toml
├── .cicd/
│   ├── config.yaml
│   └── repo-context.md
├── cicd/                              # vendored CICD module
└── .github/
    ├── CODEOWNERS
    ├── PULL_REQUEST_TEMPLATE.md
    └── workflows/
        ├── cicd.yml
        └── cicd-cleanup.yml
```
