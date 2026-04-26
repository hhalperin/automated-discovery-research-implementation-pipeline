# TLDR Reader — Probe (read-only capability check)

You are running a **probe** run, not production. Goal: verify the environment can support the TLDR Reader automation **before** enabling schedules or relying on unattended runs.

## Constraints

- **Read-only by default:** exercise `web_fetch`, **memory** (read paths), and **GitHub read** (e.g. list/search issues or read repo metadata). Do **not** create issues, PRs, or commits unless the operator explicitly enabled the optional GitHub write probe (see below).
- **Low cost:** minimal model use; no deep dives; no full-repo ingestion.
- **Deterministic output:** emit **one JSON object** only between the markers below—no markdown fences, no commentary outside the markers.

## Optional: GitHub write probe (opt-in)

If the operator message explicitly says `PROBE_ALLOW_GITHUB_WRITE=true`, you may create a **single** test issue in the designated repo with title `TLDR Reader probe (safe to close)` and body `Automated probe; safe to delete.` If that permission is not granted, set `github_write.status` to `not_attempted` and do not write.

## Checks to perform

1. **web_fetch:** GET `https://tldr.tech/tech/{YYYY-MM-DD}` (today’s date, UTC). Pass if HTTP 200 and non-empty text body after stripping boilerplate; fail on repeated failure; `skip` only if the operator disabled web tools (record reason).
2. **memory_read:** Confirm readable artifacts exist at the paths in `automation-spec.yaml` → `memory_paths` (at least `codebase_registry` and `repo_summaries`). Pass if readable; fail if missing or unreadable.
3. **github_read:** Confirm you can read GitHub context for the configured repository (e.g. default branch, labels, or a harmless search). Pass if API/read succeeds; fail if access denied.
4. **github_write:** Only if `PROBE_ALLOW_GITHUB_WRITE=true` per above; otherwise `not_attempted`.

## `ready_for_production` decision rule

Set `ready_for_production` to **true** only if **all** of the following hold:

- `web_fetch` is `pass`
- `memory_read` is `pass`
- `github_read` is `pass`
- `github_write` is **not** `fail` (either `pass`, `not_attempted`, or `skip` when write was not required)

If any required check is `fail`, set `ready_for_production` to **false** and list blocking reasons in `blocking_reasons[]`.

## Output format (required)

Emit **exactly** one JSON object between these lines (inclusive boundaries for parsers):

```
BEGIN PROBE REPORT JSON
```

```
END PROBE REPORT JSON
```

### JSON schema (informal)

- `probe_version`: `"1"`
- `date_utc`: ISO date `YYYY-MM-DD`
- `checks`: object with `web_fetch`, `memory_read`, `github_read`, `github_write` each having `status` (`pass` | `fail` | `skip` | `not_attempted`) and `detail` (string)
- `ready_for_production`: boolean
- `blocking_reasons`: string array (empty if ready)
- `notes`: optional string

No other text before `BEGIN` or after `END`.
