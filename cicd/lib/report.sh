#!/usr/bin/env bash
# cicd/lib/report.sh — aggregate .cicd/out/{checks,judges}/*.json into:
#   * .cicd/out/report.md   (sticky PR comment body)
#   * .cicd/out/labels.txt  (one label per line, for GH labeler)
#   * .cicd/out/summary.json
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

summary_file="$CICD_OUT/summary.json"
report_file="$CICD_OUT/report.md"
labels_file="$CICD_OUT/labels.txt"

# Build a machine-readable summary.
python3 - "$summary_file" "$CICD_OUT/checks" "$CICD_OUT/judges" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
checks_dir = pathlib.Path(sys.argv[2])
judges_dir = pathlib.Path(sys.argv[3])
def load(dir_path):
    items = []
    if not dir_path.is_dir():
        return items
    for p in sorted(dir_path.glob("*.json")):
        try:
            items.append(json.loads(p.read_text()))
        except Exception as e:
            items.append({"kind":"error","name":p.stem,"status":"fail","summary":f"invalid JSON: {e}","details":None})
    return items
checks = load(checks_dir)
judges = load(judges_dir)
def bucket(items, status):
    return [i for i in items if i.get("status") == status]
gate_fail = bool(bucket(checks, "fail"))
summary = {
    "gate_status": "fail" if gate_fail else "pass",
    "totals": {
        "checks": {s: len(bucket(checks, s)) for s in ("pass","fail","warn","skipped")},
        "judges": {s: len(bucket(judges, s)) for s in ("pass","fail","warn","skipped")},
    },
    "checks": checks,
    "judges": judges,
}
out.write_text(json.dumps(summary, indent=2))
PY

summary=$(cat "$summary_file")

# Render the sticky PR comment.
{
    echo "<!-- cicd:sticky -->"
    gate_status=$(jq -r '.gate_status' <<<"$summary")
    case "$gate_status" in
        pass) echo "### CICD — all gates passed" ;;
        fail) echo "### CICD — one or more gates failed" ;;
        *)    echo "### CICD" ;;
    esac
    echo ""
    echo "| Gate | Status | Summary |"
    echo "|------|--------|---------|"
    jq -r '.checks[] | "| \(.name) | \(.status) | \((.summary // "" ) | gsub("\\|";"\\|")) |"' <<<"$summary"
    echo ""
    if (( $(jq '.judges | length' <<<"$summary") > 0 )); then
        echo "| Judge | Verdict | Score | Rationale |"
        echo "|-------|---------|-------|-----------|"
        jq -r '.judges[] | "| \(.name) | \(.details.verdict // "n/a") | \(.details.score // "n/a") | \((.details.rationale // "" ) | gsub("\\|";"\\|") | gsub("\n"; " ") | .[0:200]) |"' <<<"$summary"
        echo ""
        echo "<details><summary>Judge suggestions</summary>"
        echo ""
        jq -r '
            .judges[] as $j
            | "**\($j.name)**"
            , ( $j.details.suggestions // [] | map("- " + .) | .[] )
            , ""
        ' <<<"$summary"
        echo "</details>"
        echo ""
    fi
    echo "Output artifacts: \`.cicd/out/\`. Re-run locally with \`cicd run\`."
} > "$report_file"

# Labels: one per line, only the most useful ones.
{
    gate_status=$(jq -r '.gate_status' <<<"$summary")
    [[ "$gate_status" == "pass" ]] && echo "cicd/passing" || echo "cicd/failing"
    jq -r '.checks[] | select(.status == "fail") | "cicd/gate-\(.name)-fail"' <<<"$summary"
    # Labels reflecting judge verdicts (advisory only).
    jq -r '.judges[] | select(.details.verdict == "regression" or .details.verdict == "fail") | "cicd/judge-\(.name)-regression"' <<<"$summary"
} | sort -u > "$labels_file"

cicd::log "report written: $report_file"
cicd::log "labels:       $labels_file"
cicd::log "summary:      $summary_file"
