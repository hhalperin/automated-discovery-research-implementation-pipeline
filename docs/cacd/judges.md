# CACD Judges

Judges are LLM-backed evaluators. They are **advisory by default** —
they post their verdict as part of the sticky PR comment but never
fail the workflow. Promote a judge to blocking by adding it to
`judges.blocking` in `.cacd/config.yaml`.

## Contract

Every judge outputs a JSON file at `.cacd/out/judges/<name>.json`
containing at minimum:

```json
{
  "verdict": "improvement | neutral | regression | pass | advisory | fail | skipped",
  "score": 0.0,                // 0..1 where defined; null if not
  "rationale": "...",          // human-readable, <= ~400 chars
  "suggestions": ["..."]       // concrete, actionable fixes
}
```

The runner wraps this in the standard `{kind, name, status, summary, details}`
envelope. The aggregator renders judges in a dedicated table in the PR
comment.

## Default judges

| Name | Purpose | Prompt file |
|------|---------|-------------|
| `improvement` | Net improvement vs baseline | `cacd/prompts/improvement.md` |
| `quality` | Rubric: clarity, testing, complexity, safety, consistency | `cacd/prompts/quality.md` |
| `docs-accuracy` | Do docs still describe reality? | `cacd/prompts/docs-accuracy.md` |

## Writing a new judge

1. Create `cacd/lib/judges/<name>.sh`:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   . "$CACD_ROOT/lib/common.sh"
   . "$CACD_ROOT/lib/judges/_runner.sh"
   cacd::judge::run <name> "$CACD_ROOT/prompts/<name>.md"
   ```

2. Create `cacd/prompts/<name>.md`. Use `{{diff}}`, `{{commits}}`,
   `{{pr_body}}`, `{{repo_context}}` placeholders. Require the LLM to
   return a JSON object.
3. Add `<name>` under `judges.enabled` in `.cacd/config.yaml`.

## Backends

`_runner.sh` picks the first available backend:

1. `cursor-agent` CLI (if present + `CURSOR_API_KEY` set).
2. `openai` Python SDK (if `OPENAI_API_KEY` set and importable).
3. `stub` — emits `verdict: skipped`.

## Repo context

Judges read `.cacd/repo-context.md` and inline it in every prompt. Keep
it concise and specific to *this* repo — it is the main lever to make
generic rubrics behave correctly for your codebase.
