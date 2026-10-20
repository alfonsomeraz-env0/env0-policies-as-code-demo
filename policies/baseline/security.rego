package env0

# Baseline security guardrails: public S3, ports open to the internet, hardened EC2.
# Every violation is a `deny`, which cancels the deployment before apply.

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# ---------------------------------------------------------------------------
# S3: no public ACLs, public access block stays on
# ---------------------------------------------------------------------------

public_acls := {"public-read", "public-read-write", "authenticated-read"}

public_access_flags := ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]

deny contains msg if {
	some rc in active_changes
	rc.type == "aws_s3_bucket_acl"
	rc.change.after.acl in public_acls
	msg := sprintf("[baseline/s3] %s uses public ACL '%s'", [rc.address, rc.change.after.acl])
}

deny contains msg if {
	some rc in active_changes
	rc.type == "aws_s3_bucket_public_access_block"
	some flag in public_access_flags
	rc.change.after[flag] == false
	msg := sprintf("[baseline/s3] %s disables %s", [rc.address, flag])
}

# ---------------------------------------------------------------------------
# Network: only web ports may face the internet. SSH, RDP, databases and
# everything else must be limited to private ranges. The allowed ports come from
# policyData (`world_open_ports`) with the default below.
# ---------------------------------------------------------------------------

world_cidrs := {"0.0.0.0/0", "::/0"}

default world_open_ports := [80, 443]

world_open_ports := input.policyData.world_open_ports

# True when the rule exposes at least one port outside world_open_ports.
# Protocol "-1" means every port.
exposes_restricted_port(protocol, _, _) if {
	protocol == "-1"
}

exposes_restricted_port(protocol, from_port, to_port) if {
	protocol in {"tcp", "udp", "6", "17"}
	some port in numbers.range(from_port, to_port)
	not port in world_open_ports
}

port_label(rule) := "all ports" if {
	rule.protocol == "-1"
}

port_label(rule) := sprintf("port %v", [rule.from]) if {
	rule.protocol != "-1"
	rule.from == rule.to
}

port_label(rule) := sprintf("ports %v-%v", [rule.from, rule.to]) if {
	rule.protocol != "-1"
	rule.from != rule.to
}

# Normalised view of every ingress rule in the plan, whatever resource type
# declared it: {address, cidrs, protocol, from, to}.
ingress_rules contains rule if {
	some rc in active_changes
	rc.type == "aws_vpc_security_group_ingress_rule"
	a := rc.change.after
	rule := {
		"address": rc.address,
		"cidrs": [object.get(a, "cidr_ipv4", null), object.get(a, "cidr_ipv6", null)],
		"protocol": object.get(a, "ip_protocol", ""),
		"from": object.get(a, "from_port", 0),
		"to": object.get(a, "to_port", 0),
	}
}

ingress_rules contains rule if {
	some rc in active_changes
	rc.type == "aws_security_group_rule"
	a := rc.change.after
	a.type == "ingress"
	rule := {
		"address": rc.address,
		"cidrs": array.concat(as_array(object.get(a, "cidr_blocks", [])), as_array(object.get(a, "ipv6_cidr_blocks", []))),
		"protocol": object.get(a, "protocol", ""),
		"from": object.get(a, "from_port", 0),
		"to": object.get(a, "to_port", 0),
	}
}

ingress_rules contains rule if {
	some rc in active_changes
	rc.type == "aws_security_group"
	some ing in as_array(object.get(rc.change.after, "ingress", []))
	rule := {
		"address": rc.address,
		"cidrs": array.concat(as_array(object.get(ing, "cidr_blocks", [])), as_array(object.get(ing, "ipv6_cidr_blocks", []))),
		"protocol": object.get(ing, "protocol", ""),
		"from": object.get(ing, "from_port", 0),
		"to": object.get(ing, "to_port", 0),
	}
}

deny contains msg if {
	some rule in ingress_rules
	some cidr in rule.cidrs
	cidr in world_cidrs
	exposes_restricted_port(rule.protocol, rule.from, rule.to)
	msg := sprintf(
		"[baseline/network] %s exposes %s to %s (only ports %s may face the internet)",
		[rule.address, port_label(rule), cidr, concat(", ", [sprintf("%v", [p]) | some p in world_open_ports])],
	)
}

# ---------------------------------------------------------------------------
# Compute: approved instance types, IMDSv2, encrypted root volume
# The allowlist comes from policyData (ENV0_POLICY_DATA_PATH) so it can be
# changed without editing the policy.
# ---------------------------------------------------------------------------

default allowed_instance_types := ["t3.micro", "t3.small", "t3.medium", "t3.large"]

allowed_instance_types := input.policyData.allowed_instance_types

deny contains msg if {
	some rc in active_changes
	rc.type == "aws_instance"
	itype := object.get(rc.change.after, "instance_type", "")
	itype != ""
	not itype in allowed_instance_types
	msg := sprintf("[baseline/compute] %s uses instance type '%s' (allowed: %s)", [rc.address, itype, concat(", ", allowed_instance_types)])
}

imdsv2_required(after) if {
	some opts in as_array(object.get(after, "metadata_options", []))
	opts.http_tokens == "required"
}

deny contains msg if {
	some rc in active_changes
	rc.type == "aws_instance"
	not imdsv2_required(rc.change.after)
	msg := sprintf("[baseline/compute] %s must set metadata_options.http_tokens = \"required\" (IMDSv2)", [rc.address])
}

root_volume_encrypted(after) if {
	some dev in as_array(object.get(after, "root_block_device", []))
	dev.encrypted == true
}

deny contains msg if {
	some rc in active_changes
	rc.type == "aws_instance"
	not root_volume_encrypted(rc.change.after)
	msg := sprintf("[baseline/compute] %s must encrypt its root volume", [rc.address])
}
