package baseline_test

# Run with: opa test policies/baseline tests/baseline -v   (or `make test`)

import data.env0
import future.keywords.if
import future.keywords.in

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

request(trigger, req_type) := {"type": req_type, "triggerName": trigger}

plan_input(changes) := {
	"plan": {"resource_changes": changes},
	"deploymentRequest": request("user", "deploy"),
}

create(address, type, after) := {
	"address": address,
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after},
}

good_tags := {"Owner": "platform", "CostCenter": "1234", "Environment": "dev"}

good_instance := {
	"instance_type": "t3.micro",
	"tags": good_tags,
	"metadata_options": [{"http_tokens": "required"}],
	"root_block_device": [{"encrypted": true}],
}

good_bucket := {"tags": good_tags}

has_msg(msgs, prefix) if {
	some m in msgs
	startswith(m, prefix)
}

# ---------------------------------------------------------------------------
# Clean path
# ---------------------------------------------------------------------------

test_clean_plan_is_allowed if {
	i := plan_input([
		create("aws_s3_bucket.app", "aws_s3_bucket", good_bucket),
		create("aws_instance.app[0]", "aws_instance", good_instance),
	])
	count(env0.deny) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

test_empty_plan_is_allowed if {
	count(env0.allow) == 1 with input as plan_input([])
}

test_non_plan_iac_is_allowed if {
	# helm / k8s deployments have no plan
	i := {"plan": null, "deploymentRequest": request("user", "deploy")}
	count(env0.deny) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------

test_public_acl_denied if {
	i := plan_input([create("aws_s3_bucket_acl.app", "aws_s3_bucket_acl", {"acl": "public-read"})])
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[baseline/s3] aws_s3_bucket_acl.app uses public ACL")
	count(env0.allow) == 0 with input as i
}

test_private_acl_allowed if {
	i := plan_input([create("aws_s3_bucket_acl.app", "aws_s3_bucket_acl", {"acl": "private"})])
	count(env0.deny) == 0 with input as i
}

test_disabled_public_access_block_denied if {
	i := plan_input([create("aws_s3_bucket_public_access_block.app", "aws_s3_bucket_public_access_block", {
		"block_public_acls": false,
		"block_public_policy": true,
		"ignore_public_acls": true,
		"restrict_public_buckets": false,
	})])
	result := env0.deny with input as i
	count(result) == 2
	has_msg(result, "[baseline/s3]")
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

ingress_rule(cidr, protocol, from_port, to_port) := create("aws_vpc_security_group_ingress_rule.x", "aws_vpc_security_group_ingress_rule", {
	"cidr_ipv4": cidr,
	"cidr_ipv6": null,
	"ip_protocol": protocol,
	"from_port": from_port,
	"to_port": to_port,
})

test_ssh_open_to_world_denied if {
	i := plan_input([ingress_rule("0.0.0.0/0", "tcp", 22, 22)])
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[baseline/network]")
}

test_port_range_covering_rdp_denied if {
	i := plan_input([ingress_rule("0.0.0.0/0", "tcp", 3000, 4000)])
	count(env0.deny) == 1 with input as i
}

test_all_traffic_open_to_world_denied if {
	i := plan_input([ingress_rule("0.0.0.0/0", "-1", null, null)])
	count(env0.deny) == 1 with input as i
}

test_https_open_to_world_allowed if {
	i := plan_input([ingress_rule("0.0.0.0/0", "tcp", 443, 443)])
	count(env0.deny) == 0 with input as i
}

test_ssh_from_private_cidr_allowed if {
	i := plan_input([ingress_rule("10.0.0.0/8", "tcp", 22, 22)])
	count(env0.deny) == 0 with input as i
}

test_ipv6_world_ssh_denied if {
	i := plan_input([create("aws_vpc_security_group_ingress_rule.v6", "aws_vpc_security_group_ingress_rule", {
		"cidr_ipv4": null,
		"cidr_ipv6": "::/0",
		"ip_protocol": "tcp",
		"from_port": 22,
		"to_port": 22,
	})])
	count(env0.deny) == 1 with input as i
}

test_inline_security_group_ssh_denied if {
	i := plan_input([create("aws_security_group.app", "aws_security_group", {
		"tags": good_tags,
		"ingress": [{
			"cidr_blocks": ["0.0.0.0/0"],
			"ipv6_cidr_blocks": [],
			"protocol": "tcp",
			"from_port": 22,
			"to_port": 22,
		}],
	})])
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[baseline/network] aws_security_group.app")
}

test_security_group_rule_ssh_denied if {
	i := plan_input([create("aws_security_group_rule.ssh", "aws_security_group_rule", {
		"type": "ingress",
		"cidr_blocks": ["0.0.0.0/0"],
		"ipv6_cidr_blocks": null,
		"protocol": "tcp",
		"from_port": 22,
		"to_port": 22,
	})])
	count(env0.deny) == 1 with input as i
}

test_egress_rule_ignored if {
	i := plan_input([create("aws_security_group_rule.out", "aws_security_group_rule", {
		"type": "egress",
		"cidr_blocks": ["0.0.0.0/0"],
		"protocol": "-1",
		"from_port": 0,
		"to_port": 0,
	})])
	count(env0.deny) == 0 with input as i
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

test_unapproved_instance_type_denied if {
	i := plan_input([create("aws_instance.app[0]", "aws_instance", object.union(good_instance, {"instance_type": "m5.4xlarge"}))])
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[baseline/compute] aws_instance.app[0] uses instance type 'm5.4xlarge'")
}

test_instance_allowlist_comes_from_policy_data if {
	i := object.union(
		plan_input([create("aws_instance.app[0]", "aws_instance", object.union(good_instance, {"instance_type": "m5.large"}))]),
		{"policyData": {"allowed_instance_types": ["m5.large"]}},
	)
	count(env0.deny) == 0 with input as i
}

test_missing_imdsv2_denied if {
	i := plan_input([create("aws_instance.app[0]", "aws_instance", object.union(good_instance, {"metadata_options": [{"http_tokens": "optional"}]}))])
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[baseline/compute]")
}

test_unencrypted_root_volume_denied if {
	i := plan_input([create("aws_instance.app[0]", "aws_instance", object.union(good_instance, {"root_block_device": [{"encrypted": false}]}))])
	count(env0.deny) == 1 with input as i
}

test_deleted_instance_not_evaluated if {
	# destroys are not "active" changes, so removing a bad instance is never blocked
	i := plan_input([{
		"address": "aws_instance.old",
		"mode": "managed",
		"type": "aws_instance",
		"change": {"actions": ["delete"], "after": null},
	}])
	count(env0.deny) == 0 with input as i
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

test_missing_tags_denied if {
	i := plan_input([create("aws_s3_bucket.app", "aws_s3_bucket", {"tags": {"Owner": "platform"}})])
	result := env0.deny with input as i
	count(result) == 2
	has_msg(result, "[baseline/tags]")
}

test_empty_tag_value_denied if {
	i := plan_input([create("aws_s3_bucket.app", "aws_s3_bucket", {"tags": object.union(good_tags, {"Owner": ""})})])
	count(env0.deny) == 1 with input as i
}

test_null_tags_denied if {
	i := plan_input([create("aws_s3_bucket.app", "aws_s3_bucket", {"tags": null})])
	count(env0.deny) == 3 with input as i
}

test_default_tags_count if {
	i := plan_input([create("aws_s3_bucket.app", "aws_s3_bucket", {"tags": null, "tags_all": good_tags})])
	count(env0.deny) == 0 with input as i
}

test_required_tags_come_from_policy_data if {
	i := object.union(
		plan_input([create("aws_s3_bucket.app", "aws_s3_bucket", good_bucket)]),
		{"policyData": {"required_tags": ["Owner", "DataClass"]}},
	)
	result := env0.deny with input as i
	count(result) == 1
	has_msg(result, "[baseline/tags] aws_s3_bucket.app is missing required tag 'DataClass'")
}

test_untaggable_types_skipped if {
	i := plan_input([create("aws_s3_bucket_versioning.app", "aws_s3_bucket_versioning", {})])
	count(env0.deny) == 0 with input as i
}

# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------

with_cost(diff, total) := object.union(plan_input([]), {"costEstimation": {"monthlyCostDiff": diff, "totalMonthlyCost": total}})

test_cost_under_thresholds_is_clean if {
	i := with_cost(5, 50)
	count(env0.warn) == 0 with input as i
	count(env0.pending) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

test_cost_warn if {
	i := with_cost(30, 80)
	count(env0.warn) == 1 with input as i
	count(env0.pending) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

test_cost_pending if {
	i := with_cost(120, 300)
	count(env0.pending) == 1 with input as i
	count(env0.allow) == 0 with input as i
}

test_cost_messages_are_readable if {
	i := with_cost(120.456, 600)
	"[baseline/cost] this change adds about $120.46/month (approval required above $100)" in env0.pending with input as i
	"[baseline/cost] environment would cost about $600/month (limit $500)" in env0.deny with input as i
}

test_cost_pending_suppressed_on_resume if {
	i := object.union(with_cost(120, 300), {"deploymentRequest": request("user", "deployResume")})
	count(env0.pending) == 0 with input as i
	count(env0.allow) == 1 with input as i
}

test_cost_deny if {
	i := with_cost(10, 600)
	count(env0.deny) == 1 with input as i
	count(env0.allow) == 0 with input as i
}

test_cost_accepts_numeric_strings if {
	i := with_cost("120.50", "300.00")
	count(env0.pending) == 1 with input as i
}

test_cost_thresholds_come_from_policy_data if {
	i := object.union(with_cost(30, 80), {"policyData": {"cost": {"warn_diff": 50}}})
	count(env0.warn) == 0 with input as i
}

test_missing_cost_estimation_warns if {
	count(env0.warn) == 1 with input as plan_input([])
	count(env0.allow) == 1 with input as plan_input([])
}
