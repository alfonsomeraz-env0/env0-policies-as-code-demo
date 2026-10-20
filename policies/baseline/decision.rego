package env0

# env zero holds for approval when no rule fires, so every policy folder must say
# `allow` explicitly for its clean path. Results are merged strictest-first:
# deny > pending > warn > allow.

import future.keywords.contains
import future.keywords.if
import future.keywords.in

allow contains msg if {
	count(deny) == 0
	count(pending) == 0
	msg := "baseline guardrails passed"
}
