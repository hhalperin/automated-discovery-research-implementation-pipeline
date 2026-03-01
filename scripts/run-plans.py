#!/usr/bin/env python3
"""
Cursor Plan Orchestrator — run each workstream plan in a separate Cursor Agent
invocation (fresh context per plan).

The Cursor Agent CLI is invoked as `agent` (see https://cursor.com/docs/cli).

Requires: `agent` on PATH, installed and authenticated.
  Install: https://cursor.com/docs/cli/installation
  Auth: CURSOR_API_KEY or `agent login`

Usage:
  python scripts/run-plans.py --all              # Run all plans in dependency order
  python scripts/run-plans.py --plan infra-bootstrap
  python scripts/run-plans.py --all --dry-run     # Print commands only
  python scripts/run-plans.py --list              # List plan IDs and order
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


# Execution order follows .cursor/plans/plan-graph.yaml dependency edges.
# Skip root (tldr-research-ops) and adr-finalization (already complete).
PLAN_ORDER = [
    "infra-bootstrap",
    "pipeline-ingestion",
    "pipeline-triage",
    "pipeline-evidence",
    "pipeline-learning",
    "pipeline-implementation",
    "pipeline-codegen",
    "ops-evaluation",
]

PROMPT_TEMPLATE = """Implement all unchecked TODOs in this plan file. Work in order by group; satisfy each acceptance criterion before moving on. Do not skip TODOs. If a TODO is blocked by missing code from a previous step, implement the prerequisite first. Output a short summary of what was done at the end.

Plan file to execute (read this file and follow it exactly):
{plan_path}
"""


def repo_root() -> Path:
    root = Path(__file__).resolve().parent.parent
    if not (root / ".cursor" / "plans").exists():
        raise SystemExit("fatal: not run from tldr repo root (no .cursor/plans/)")
    return root


def plan_file(root: Path, plan_id: str) -> Path:
    path = root / ".cursor" / "plans" / f"{plan_id}.plan.md"
    if not path.exists():
        raise SystemExit(f"fatal: plan file not found: {path}")
    return path


def run_plan(
    root: Path,
    plan_id: str,
    *,
    dry_run: bool,
    force: bool,
    trust: bool,
    log_path: Path | None,
    agent_cmd: str,
) -> int:
    plan_path = plan_file(root, plan_id)
    prompt = PROMPT_TEMPLATE.format(plan_path=plan_path)

    cmd = [
        agent_cmd,
        "-p",
        "--force" if force else None,
        "--trust" if trust else None,
        "--workspace",
        str(root),
        prompt,
    ]
    cmd = [x for x in cmd if x is not None]

    if dry_run:
        print(f"[dry-run] {plan_id}")
        print("  ", " \\\n   ".join(cmd))
        if log_path:
            print(f"  log: {log_path}")
        return 0

    print(f"Running plan: {plan_id} (new context)")
    if log_path:
        print(f"  logging to {log_path}")

    out = subprocess.DEVNULL if not log_path else open(log_path, "w", encoding="utf-8")
    err = subprocess.STDOUT if log_path else None
    try:
        result = subprocess.run(
            cmd,
            cwd=root,
            stdout=out,
            stderr=err,
            env={**os.environ},
        )
    finally:
        if log_path and out != subprocess.DEVNULL:
            out.close()

    if result.returncode != 0:
        print(f"  exit code {result.returncode}")
    else:
        print(f"  done (exit 0)")
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Orchestrate Cursor Agent to run each plan in a separate context.",
        epilog="Set CURSOR_AGENT_CMD to override the agent binary (e.g. 'cursor agent' or full path).",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Run all plans in dependency order (one agent invocation per plan).",
    )
    parser.add_argument(
        "--plan",
        metavar="PLAN_ID",
        help="Run a single plan by planId (e.g. infra-bootstrap).",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List plan IDs in execution order and exit.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands only; do not invoke the agent.",
    )
    parser.add_argument(
        "--no-force",
        action="store_true",
        help="Do not pass --force to agent (changes only proposed, not applied).",
    )
    parser.add_argument(
        "--no-trust",
        action="store_true",
        help="Do not pass --trust to agent (may prompt in headless).",
    )
    parser.add_argument(
        "--log-dir",
        metavar="DIR",
        default=".cursor/plan-logs",
        help="Directory for per-plan log files (default: .cursor/plan-logs). Disable with --no-log-dir.",
    )
    parser.add_argument(
        "--no-log-dir",
        action="store_true",
        help="Do not write per-plan log files; agent output goes to stdout/stderr.",
    )
    parser.add_argument(
        "--agent-cmd",
        default=os.environ.get("CURSOR_AGENT_CMD", "agent"),
        help="Agent binary (default: agent or CURSOR_AGENT_CMD).",
    )
    args = parser.parse_args()

    root = repo_root()

    if args.list:
        for i, plan_id in enumerate(PLAN_ORDER, 1):
            path = plan_file(root, plan_id)
            print(f"  {i}. {plan_id}  ({path.relative_to(root)})")
        return 0

    if not args.all and not args.plan:
        parser.error("specify --all or --plan PLAN_ID (or --list)")

    if args.plan:
        if args.plan not in PLAN_ORDER:
            print(f"unknown plan: {args.plan}", file=sys.stderr)
            print("known plans:", ", ".join(PLAN_ORDER), file=sys.stderr)
            return 1
        plans_to_run = [args.plan]
    else:
        plans_to_run = list(PLAN_ORDER)

    log_dir = None
    if not args.no_log_dir and args.log_dir:
        log_dir = root / args.log_dir
        if not args.dry_run:
            log_dir.mkdir(parents=True, exist_ok=True)

    force = not args.no_force
    trust = not args.no_trust

    failed = []
    for plan_id in plans_to_run:
        log_path = (log_dir / f"{plan_id}.log") if log_dir else None
        code = run_plan(
            root,
            plan_id,
            dry_run=args.dry_run,
            force=force,
            trust=trust,
            log_path=log_path,
            agent_cmd=args.agent_cmd,
        )
        if code != 0:
            failed.append(plan_id)
            if args.all:
                print(f"Stopping after first failure: {plan_id}")
                break

    if failed:
        print(f"Failed plans: {', '.join(failed)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
