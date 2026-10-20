package env0

# Shared helpers for the baseline approval policy.
#
# env zero loads every .rego file in a policy folder into one `package env0`, so
# rules in the other files of this folder can use anything defined here.
#
# The `future.keywords` imports are deliberate: they let the same files parse on
# older OPA builds (CI runs 0.46.1) and on OPA 1.x. Pin the version env zero
# uses with the ENV0_OPA_VERSION environment variable if you need to.

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# True on the post-approval re-evaluation (deployResume / destroyResume).
# `pending` rules must not fire on that pass or the deployment loops forever
# (approve -> re-hold).
is_resume if {
	endswith(input.deploymentRequest.type, "Resume")
}

default resource_changes := []

resource_changes := input.plan.resource_changes

# Managed resources the plan creates or updates (a replace is delete + create).
active_changes := [rc |
	some rc in resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
]

as_object(x) := x if {
	is_object(x)
}

as_object(x) := {} if {
	not is_object(x)
}

as_array(x) := x if {
	is_array(x)
}

as_array(x) := [] if {
	not is_array(x)
}

# Effective tags: provider default_tags (tags_all) overlaid with resource tags.
tags_of(after) := object.union(
	as_object(object.get(after, "tags_all", {})),
	as_object(object.get(after, "tags", {})),
)
