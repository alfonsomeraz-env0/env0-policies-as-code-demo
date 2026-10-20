variable "name_prefix" {
  description = "Prefix for every env0 object this module creates"
  type        = string
  default     = "pac-demo"
}

variable "repo_url" {
  description = "Git URL of this repository, as env0 sees it (holds app/ and policies/)"
  type        = string
}

variable "repo_revision" {
  description = "Branch or tag env0 reads templates and policies from"
  type        = string
  default     = "main"
}

variable "vcs_connection_id" {
  description = "env0 VCS connection id for repo_url. Leave null for a public repository"
  type        = string
  default     = null
}

variable "opentofu_version" {
  description = "OpenTofu version for the app template"
  type        = string
  default     = "latest"
}

variable "cloud_credentials_id" {
  description = "Optional env0 AWS cloud credentials id to attach to both projects"
  type        = string
  default     = null
}

variable "dev_monthly_budget" {
  description = "Monthly budget (USD) for the dev project"
  type        = number
  default     = 200
}
