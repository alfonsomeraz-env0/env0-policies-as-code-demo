package env0

# Cost guardrails, driven by env0 cost estimation (input.costEstimation).
# Turn on "Include cost estimation" in the project policy or these rules are
# skipped (and a warning says so).
#
#   monthly diff  > warn_diff     -> warn    (continues)
#   monthly diff  > pending_diff  -> pending (needs a human)
#   monthly total > deny_total    -> deny    (cancelled)
#
# Thresholds come from policyData.cost, with the defaults below.

import future.keywords.contains
import future.keywords.if
import future.keywords.in

default warn_diff := 25

default pending_diff := 100

default deny_total := 500

warn_diff := input.policyData.cost.warn_diff

pending_diff := input.policyData.cost.pending_diff

deny_total := input.policyData.cost.deny_total

# env0 may send these as numbers or strings, so normalise.
monthly_diff := to_number(input.costEstimation.monthlyCostDiff)

monthly_total := to_number(input.costEstimation.totalMonthlyCost)

# Two decimals for messages. sprintf("%.2f") mangles integer-valued numbers in OPA.
money(x) := round(x * 100) / 100

warn contains msg if {
	not input.costEstimation
	msg := "[baseline/cost] cost estimation is not available, cost guardrails skipped"
}

warn contains msg if {
	monthly_diff > warn_diff
	msg := sprintf("[baseline/cost] this change adds about $%v/month (warn above $%v)", [money(monthly_diff), warn_diff])
}

pending contains msg if {
	not is_resume
	monthly_diff > pending_diff
	msg := sprintf("[baseline/cost] this change adds about $%v/month (approval required above $%v)", [money(monthly_diff), pending_diff])
}

deny contains msg if {
	monthly_total > deny_total
	msg := sprintf("[baseline/cost] environment would cost about $%v/month (limit $%v)", [money(monthly_total), deny_total])
}
