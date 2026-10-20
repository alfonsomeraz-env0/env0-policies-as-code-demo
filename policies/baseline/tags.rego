package env0

# Mandatory tags on taggable resources. The list comes from policyData
# (`required_tags`) and falls back to the default below.

import future.keywords.contains
import future.keywords.if
import future.keywords.in

default required_tags := ["Owner", "CostCenter", "Environment"]

required_tags := input.policyData.required_tags

taggable_types := {"aws_s3_bucket", "aws_instance", "aws_security_group"}

tag_missing(tags, key) if {
	not tags[key]
}

tag_missing(tags, key) if {
	tags[key] == ""
}

deny contains msg if {
	some rc in active_changes
	rc.type in taggable_types
	tags := tags_of(rc.change.after)
	some key in required_tags
	tag_missing(tags, key)
	msg := sprintf("[baseline/tags] %s is missing required tag '%s'", [rc.address, key])
}
