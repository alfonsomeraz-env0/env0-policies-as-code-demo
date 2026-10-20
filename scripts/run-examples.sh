#!/usr/bin/env bash
# Run the sample plans in examples/plans through the policies and check each
# outcome. Needs only opa and jq, no AWS or env zero account.
#
#   scripts/run-examples.sh
#
# Outcome is the strictest result: DENY > PENDING > WARN > ALLOW. A plan with no
# cost estimate gets a "cost unavailable" WARN, so every row below passes a
# cheap estimate unless the row is about cost.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
plans="$root/examples/plans"

# plan | policy | trigger | cost diff | cost total | expected
rows='
01-clean|baseline|cd|5|20|ALLOW
01-clean|baseline|cd|30|80|WARN
01-clean|baseline|cd|120|300|PENDING
01-clean|baseline|cd|10|600|DENY
01-clean|production|cd|5|20|ALLOW
01-clean|production|user|5|20|PENDING
02-public-bucket|baseline|cd|5|20|DENY
03-open-database|baseline|cd|5|20|DENY
04-open-ssh|baseline|cd|5|20|DENY
05-missing-tags|baseline|cd|5|20|DENY
06-bad-instance-type|baseline|cd|5|20|DENY
07-insecure-compute|baseline|cd|5|20|DENY
10-prod-delete|baseline|cd|0|20|ALLOW
10-prod-delete|production|cd|0|20|PENDING
'

failed=0
printf '%-22s %-11s %-8s %-12s %-9s %s\n' PLAN POLICY TRIGGER COST EXPECTED ACTUAL
while IFS='|' read -r plan policy trigger diff total expected; do
  [ -n "$plan" ] || continue
  result="$(TRIGGER="$trigger" COST_DIFF="$diff" COST_TOTAL="$total" \
    "$root/scripts/eval-plan.sh" "$policy" "$plans/$plan.json")"
  actual="$(printf '%s' "$result" | jq -r '
    if (.deny | length) > 0 then "DENY"
    elif (.pending | length) > 0 then "PENDING"
    elif (.warn | length) > 0 then "WARN"
    elif (.allow | length) > 0 then "ALLOW"
    else "NONE" end')"
  mark=ok
  if [ "$actual" != "$expected" ]; then mark=MISMATCH; failed=1; fi
  printf '%-22s %-11s %-8s %-12s %-9s %s %s\n' \
    "$plan" "$policy" "$trigger" "+\$$diff/\$$total" "$expected" "$actual" "$([ $mark = ok ] || echo "<-- $mark")"
done <<< "$rows"

exit "$failed"
