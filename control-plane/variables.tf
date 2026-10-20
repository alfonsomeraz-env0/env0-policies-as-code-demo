variable "name_prefix" {
  description = "Prefix for every env zero object this module creates"
  type        = string
  default     = "pac-demo"
}

variable "repo_url" {
  description = "Git URL of this repository, as env zero sees it (holds app/ and policies/)"
  type        = string
}

variable "repo_revision" {
  description = "Branch or tag env zero reads templates and policies from"
  type        = string
  default     = "main"
}

variable "vcs_connection_id" {
  description = "env zero VCS connection id for repo_url. Leave null for a public repository"
  type        = string
  default     = null
}

variable "opentofu_version" {
  description = "OpenTofu version for the app template"
  type        = string
  default     = "latest"
}

variable "cloud_credentials_id" {
  description = "Optional env zero AWS cloud credentials id to attach to both projects"
  type        = string
  default     = null
}

variable "dev_monthly_budget" {
  description = "Monthly budget (USD) for the dev project"
  type        = number
  default     = 200
}

variable "parent_project_id" {
  description = "Optional env zero project to nest the demo project under. Null creates it at the root."
  type        = string
  default     = null
}
