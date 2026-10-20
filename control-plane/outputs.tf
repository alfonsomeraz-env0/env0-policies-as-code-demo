output "project_ids" {
  description = "env0 project ids"
  value = {
    parent = env0_project.parent.id
    dev    = env0_project.dev.id
    prod   = env0_project.prod.id
  }
}

output "approval_policy_ids" {
  description = "env0 approval policy ids"
  value = {
    baseline   = env0_approval_policy.baseline.id
    production = env0_approval_policy.production.id
  }
}

output "template_id" {
  description = "env0 template id for the demo app"
  value       = env0_template.app.id
}
