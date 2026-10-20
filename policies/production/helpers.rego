package env0

# Shared helpers for the production approval policy (see baseline/helpers.rego
# for why the future.keywords imports are there).

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# True on the post-approval re-evaluation (deployResume / destroyResume).
is_resume if {
	endswith(input.deploymentRequest.type, "Resume")
}

default resource_changes := []

resource_changes := input.plan.resource_changes

# Managed resources that actually change (anything but a no-op).
changed_resources := [rc |
	some rc in resource_changes
	rc.mode == "managed"
	rc.change.actions != ["no-op"]
]

# Managed resources the plan deletes or replaces.
destructive_changes := [rc |
	some rc in changed_resources
	"delete" in rc.change.actions
]
