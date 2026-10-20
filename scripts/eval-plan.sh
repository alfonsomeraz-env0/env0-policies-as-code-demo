#!/usr/bin/env bash
# Evaluate an approval policy folder against a plan JSON, locally, with the same
# input shape env0 builds (plan, deploymentRequest, policyData, costEstimation).
#
#   scripts/plan-json.sh 02-public-bucket > /tmp/plan.json
#   scripts/eval-plan.sh baseline /tmp/plan.json
#   TRIGGER=user COST_DIFF=120 COST_TOTAL=300 scripts/eval-plan.sh production /tmp/plan.json
#
# Env:
#   TRIGGER      deploymentRequest.triggerName (default: cd)
#   REQUEST_TYPE deploymentRequest.type        (default: deploy)
#   POLICY_DATA  policy data JSON              (default: app/policy_data.json)
#   COST_DIFF / COST_TOTAL   set both to add a costEstimation block
#
# Prints the merged deny / pending / warn / allow sets.
set -euo pipefail

policy="${1:?usage: eval-plan.sh <baseline|production> <plan.json>}"
plan="${2:?usage: eval-plan.sh <baseline|production> <plan.json>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/policies/$policy"
data="${POLICY_DATA:-$root/app/policy_data.json}"

[ -d "$dir" ] || { echo "no such policy folder: $dir" >&2; exit 1; }
command -v opa > /dev/null || { echo "opa not found on PATH" >&2; exit 1; }

jq -n \
  --slurpfile plan "$plan" \
  --slurpfile data "$data" \
  --arg trigger "${TRIGGER:-cd}" \
  --arg type "${REQUEST_TYPE:-deploy}" \
  --arg diff "${COST_DIFF:-}" \
  --arg total "${COST_TOTAL:-}" '
  {
    plan: $plan[0],
    deploymentRequest: {type: $type, triggerName: $trigger},
    policyData: $data[0]
  }
  + (if $diff != "" and $total != ""
     then {costEstimation: {monthlyCostDiff: ($diff | tonumber), totalMonthlyCost: ($total | tonumber)}}
     else {} end)
' | opa eval \
  --format json \
  --data "$dir" \
  --stdin-input \
  'data.env0' \
  | jq '.result[0].expressions[0].value
        | {deny: (.deny // []), pending: (.pending // []), warn: (.warn // []), allow: (.allow // [])}'
