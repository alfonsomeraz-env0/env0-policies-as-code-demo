# ---------------------------------------------------------------------------
# Projects: a parent with two children.
#   parent  -> baseline approval policy (inherited by dev and prod)
#   prod    -> baseline (inherited) + production approval policy
# ---------------------------------------------------------------------------

resource "env0_project" "parent" {
  name        = var.name_prefix
  description = "Policies as code demo. Approval policies are managed from the policies/ folder of the demo repo."
}

resource "env0_project" "dev" {
  name              = "${var.name_prefix}-dev"
  description       = "Dev: baseline guardrails only"
  parent_project_id = env0_project.parent.id
}

resource "env0_project" "prod" {
  name              = "${var.name_prefix}-prod"
  description       = "Prod: baseline guardrails plus production change control"
  parent_project_id = env0_project.parent.id
}

# ---------------------------------------------------------------------------
# Approval policies (OPA / Rego, package env0). One policy = one folder.
# ---------------------------------------------------------------------------

resource "env0_approval_policy" "baseline" {
  name              = "${var.name_prefix}-baseline"
  repository        = var.repo_url
  path              = "policies/baseline"
  revision          = var.repo_revision
  vcs_connection_id = var.vcs_connection_id
}

resource "env0_approval_policy" "production" {
  name              = "${var.name_prefix}-production"
  repository        = var.repo_url
  path              = "policies/production"
  revision          = var.repo_revision
  vcs_connection_id = var.vcs_connection_id
}

resource "env0_approval_policy_assignment" "baseline" {
  scope        = "PROJECT"
  scope_id     = env0_project.parent.id
  blueprint_id = env0_approval_policy.baseline.id
}

resource "env0_approval_policy_assignment" "production" {
  scope        = "PROJECT"
  scope_id     = env0_project.prod.id
  blueprint_id = env0_approval_policy.production.id
}

# ---------------------------------------------------------------------------
# Template: the demo app, with the policy-data path wired in.
# ---------------------------------------------------------------------------

resource "env0_template" "app" {
  name              = "${var.name_prefix}-app"
  description       = "Demo app that trips (or passes) each policy depending on its variables"
  type              = "opentofu"
  repository        = var.repo_url
  path              = "app"
  revision          = var.repo_revision
  opentofu_version  = var.opentofu_version
  vcs_connection_id = var.vcs_connection_id
}

resource "env0_template_project_assignment" "dev" {
  template_id = env0_template.app.id
  project_id  = env0_project.dev.id
}

resource "env0_template_project_assignment" "prod" {
  template_id = env0_template.app.id
  project_id  = env0_project.prod.id
}

# Relative path: env0 shares the working directory between the plan step and the
# policy check, but not /tmp.
resource "env0_configuration_variable" "policy_data_path" {
  name        = "ENV0_POLICY_DATA_PATH"
  value       = "policy_data.json"
  description = "JSON file exposed to the approval policies as input.policyData"
  template_id = env0_template.app.id
}

# Dumps the full policy input into the deploy log. Useful on stage, noisy otherwise.
resource "env0_configuration_variable" "print_policy_input" {
  name        = "ENV0_PRINT_POLICY_INPUT"
  value       = "true"
  description = "Print the approval policy input in the deployment log"
  template_id = env0_template.app.id
}

resource "env0_configuration_variable" "environment_dev" {
  name       = "environment"
  value      = "dev"
  type       = "terraform"
  project_id = env0_project.dev.id
}

resource "env0_configuration_variable" "environment_prod" {
  name       = "environment"
  value      = "prod"
  type       = "terraform"
  project_id = env0_project.prod.id
}

# ---------------------------------------------------------------------------
# Project policies and budget. Cost estimation must be on or the baseline cost
# rules have nothing to evaluate.
# ---------------------------------------------------------------------------

resource "env0_project_policy" "dev" {
  project_id                    = env0_project.dev.id
  include_cost_estimation       = true
  skip_apply_when_plan_is_empty = true
  skip_redundant_deployments    = true
  number_of_environments        = 5
  default_ttl                   = "1-d"
  max_ttl                       = "1-w"
}

resource "env0_project_policy" "prod" {
  project_id                    = env0_project.prod.id
  include_cost_estimation       = true
  skip_apply_when_plan_is_empty = true
  skip_redundant_deployments    = true
  drift_detection_cron          = "0 4 * * *"
  auto_drift_remediation        = "DISABLED"
}

resource "env0_project_budget" "dev" {
  project_id = env0_project.dev.id
  amount     = var.dev_monthly_budget
  timeframe  = "MONTHLY"
  thresholds = [50, 80, 100]
}

resource "env0_cloud_credentials_project_assignment" "dev" {
  count = var.cloud_credentials_id == null ? 0 : 1

  credential_id = var.cloud_credentials_id
  project_id    = env0_project.dev.id
}

resource "env0_cloud_credentials_project_assignment" "prod" {
  count = var.cloud_credentials_id == null ? 0 : 1

  credential_id = var.cloud_credentials_id
  project_id    = env0_project.prod.id
}
