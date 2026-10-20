package production_test

# Run with: opa test policies/production tests/production -v   (or `make test`)

import data.env0
import future.keywords.if
import future.keywords.in

request(trigger, req_type) := {"type": req_type, "triggerName": trigger}

change(address, type, actions) := {
	"address": address,
	"mode": "managed",
	"type": type,
	"change": {"actions": actions},
}

plan_input(trigger, req_type, changes) := {
	"plan": {"resource_changes": changes},
	"deploymentRequest": request(trigger, req_type),
	"deployerUser": {"name": "Dana", "email": "dana@example.com"},
}

routine := [change("aws_s3_bucket.app", "aws_s3_bucket", ["update"])]

has_msg(msgs, prefix) if {
	some m in msgs
	startswith(m, prefix)
}

# ---------------------------------------------------------------------------
# Routine changes
# ---------------------------------------------------------------------------

test_routine_cd_change_auto_approved if {
	i := plan_input("cd", "deploy", routine)
	count(env0.deny) == 0 with input as i
	count(env0.pending) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

test_noop_resources_ignored if {
	i := plan_input("cd", "deploy", [change("aws_s3_bucket.app", "aws_s3_bucket", ["no-op"]), change("aws_iam_role.x", "aws_iam_role", ["no-op"])])
	count(env0.pending) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

# ---------------------------------------------------------------------------
# Pending
# ---------------------------------------------------------------------------

test_delete_needs_approval if {
	i := plan_input("cd", "deploy", [change("aws_s3_bucket.logs[0]", "aws_s3_bucket", ["delete"])])
	result := env0.pending with input as i
	count(result) == 1
	has_msg(result, "[production/destructive] aws_s3_bucket.logs[0]")
	count(env0.allow) == 0 with input as i
}

test_replace_needs_approval if {
	i := plan_input("cd", "deploy", [change("aws_instance.app[0]", "aws_instance", ["delete", "create"])])
	count(env0.pending) == 1 with input as i
}

test_iam_change_needs_approval if {
	i := plan_input("cd", "deploy", [change("aws_iam_role.deploy", "aws_iam_role", ["create"])])
	result := env0.pending with input as i
	count(result) == 1
	has_msg(result, "[production/sensitive]")
}

test_security_group_rule_edit_needs_approval if {
	i := plan_input("cd", "deploy", [change("aws_vpc_security_group_ingress_rule.https", "aws_vpc_security_group_ingress_rule", ["update"])])
	count(env0.pending) == 1 with input as i
}

test_new_security_group_is_routine if {
	i := plan_input("cd", "deploy", [
		change("aws_security_group.app", "aws_security_group", ["create"]),
		change("aws_vpc_security_group_ingress_rule.https", "aws_vpc_security_group_ingress_rule", ["create"]),
	])
	count(env0.pending) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

test_manual_trigger_needs_approval if {
	i := plan_input("user", "deploy", routine)
	result := env0.pending with input as i
	count(result) == 1
	has_msg(result, "[production/trigger] 'user'")
	count(env0.allow) == 0 with input as i
}

test_scheduled_trigger_needs_approval if {
	i := plan_input("scheduled", "deploy", routine)
	count(env0.pending) == 1 with input as i
}

# ---------------------------------------------------------------------------
# Resume pass (after a human approved)
# ---------------------------------------------------------------------------

test_resume_after_independent_approval_allowed if {
	i := object.union(plan_input("user", "deployResume", [change("aws_s3_bucket.logs[0]", "aws_s3_bucket", ["delete"])]), {"approvers": [{"name": "Sam", "email": "sam@example.com"}]})
	count(env0.pending) == 0 with input as i
	count(env0.deny) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

test_resume_without_approver_data_allowed if {
	i := plan_input("user", "destroyResume", [change("aws_s3_bucket.logs[0]", "aws_s3_bucket", ["delete"])])
	count(env0.allow) == 1 with input as i
}

test_self_approval_denied if {
	i := object.union(plan_input("user", "deployResume", routine), {"approvers": [{"name": "Dana", "email": "dana@example.com"}]})
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[production/separation-of-duties]")
	count(env0.allow) == 0 with input as i
}

test_self_approval_with_second_approver_allowed if {
	i := object.union(plan_input("user", "deployResume", routine), {"approvers": [{"email": "dana@example.com"}, {"email": "sam@example.com"}]})
	count(env0.deny) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

# ---------------------------------------------------------------------------
# Change freeze
# ---------------------------------------------------------------------------

test_change_freeze_denies_everything if {
	i := object.union(plan_input("cd", "deploy", routine), {"policyData": {"change_freeze": true}})
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[production/freeze]")
	count(env0.allow) == 0 with input as i
}

test_freeze_flag_false_is_ignored if {
	i := object.union(plan_input("cd", "deploy", routine), {"policyData": {"change_freeze": false}})
	count(env0.deny) == 0 with input as i
	count(env0.allow) == 1 with input as i
}
