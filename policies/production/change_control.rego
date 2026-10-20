package env0

# Production change control. Layered on top of the baseline policy (assigned to
# the parent project), so prod environments are evaluated against both.
#
#   change freeze flag set                    -> deny
#   requester is the only approver            -> deny   (separation of duties)
#   deletes or replaces a resource            -> pending
#   touches IAM / KMS, or edits a security group rule -> pending
#   not a continuous-deployment trigger       -> pending
#   routine `cd` change, nothing above        -> allow  (auto-approved)

import future.keywords.contains
import future.keywords.every
import future.keywords.if
import future.keywords.in

# Triggers that may be auto-approved when the change is routine.
auto_approve_triggers := {"cd"}

# Any change to IAM or KMS needs a human. Security group rules only when an
# existing one is modified or removed; creating a new rule is covered by the
# baseline policy (no world-open SSH/RDP).
access_prefixes := ["aws_iam_", "aws_kms_"]

network_prefixes := ["aws_security_group", "aws_vpc_security_group"]

access_changes := [rc |
	some rc in changed_resources
	some prefix in access_prefixes
	startswith(rc.type, prefix)
]

network_edits := [rc |
	some rc in changed_resources
	some prefix in network_prefixes
	startswith(rc.type, prefix)
	rc.change.actions != ["create"]
]

sensitive_changes := array.concat(access_changes, network_edits)

# ---------------------------------------------------------------------------
# deny
# ---------------------------------------------------------------------------

# policyData.change_freeze is the kill switch. A custom flow can set it from a
# calendar or feature flag; in this demo it is a value in policy_data.json.
deny contains msg if {
	input.policyData.change_freeze == true
	msg := "[production/freeze] change freeze is active, no production deployments"
}

# After a human approves, env zero re-evaluates the policy (deployResume). Block the
# deployment if the requester approved their own change.
deny contains msg if {
	is_resume
	count(input.approvers) > 0
	every approver in input.approvers {
		approver.email == input.deployerUser.email
	}
	msg := "[production/separation-of-duties] the requester cannot be the only approver"
}

# ---------------------------------------------------------------------------
# pending (initial request only, never on the resume pass)
# ---------------------------------------------------------------------------

pending contains msg if {
	not is_resume
	some rc in destructive_changes
	msg := sprintf("[production/destructive] %s is deleted or replaced", [rc.address])
}

pending contains msg if {
	not is_resume
	some rc in sensitive_changes
	msg := sprintf("[production/sensitive] %s changes access or security configuration", [rc.address])
}

pending contains msg if {
	not is_resume
	not input.deploymentRequest.triggerName in auto_approve_triggers
	msg := sprintf("[production/trigger] '%s' deployments need approval", [input.deploymentRequest.triggerName])
}

# ---------------------------------------------------------------------------
# allow
# ---------------------------------------------------------------------------

allow contains msg if {
	not is_resume
	count(deny) == 0
	count(pending) == 0
	msg := "production: routine continuous-deployment change, auto-approved"
}

allow contains msg if {
	is_resume
	count(deny) == 0
	msg := "production: resumed after independent approval"
}
