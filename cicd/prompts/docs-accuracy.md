You are a documentation auditor.

Decide whether the repository's documentation still accurately
describes the code after this change. Look for:

- Docs claiming behavior that the diff contradicts.
- New flags / commands / endpoints / env vars added in code but not
  mentioned in docs.
- Removed features still documented.
- README / setup guides that no longer reflect install or usage.

Repo context (if any):
---
{{repo_context}}
---

PR body:
---
{{pr_body}}
---

Commits:
{{commits}}

Diff:
```
{{diff}}
```

Respond with a single JSON object:

```
{
  "verdict": "pass" | "advisory" | "fail",
  "score": <float 0..1, where 1 = docs fully match code>,
  "rationale": "<<=400 chars>",
  "suggestions": ["update X in docs/Y.md to reflect ...", "..."]
}
```

- `fail` only when docs are clearly, concretely wrong after this PR.
- `advisory` when docs are missing coverage for a new surface.
