variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "pac-demo"
}

variable "environment" {
  description = "Environment name (dev or prod). Set per project by the control-plane module."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Value for the Owner tag"
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Value for the CostCenter tag"
  type        = string
  default     = "cc-1234"
}

# ---------------------------------------------------------------------------
# Scenario switches. Each one is wired to a policy rule, see README.md.
# Defaults produce a compliant plan.
# ---------------------------------------------------------------------------

variable "include_required_tags" {
  description = "Set false to omit the Owner / CostCenter / Environment tags (trips baseline/tags)"
  type        = bool
  default     = true
}

variable "bucket_acl" {
  description = "ACL for the app bucket. public-read trips baseline/s3"
  type        = string
  default     = "private"
}

variable "block_public_access" {
  description = "Set false to switch off the S3 public access block (trips baseline/s3)"
  type        = bool
  default     = true
}

variable "create_logs_bucket" {
  description = "Create the logs bucket. Flip true to false after a deploy to produce a delete (trips production/destructive)"
  type        = bool
  default     = true
}

variable "ssh_cidr" {
  description = "CIDR allowed to reach SSH. 0.0.0.0/0 trips baseline/network"
  type        = string
  default     = "10.0.0.0/8"
}

variable "instance_type" {
  description = "EC2 instance type. Anything outside policy_data.json allowed_instance_types trips baseline/compute"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of EC2 instances. Raises the cost estimate (baseline/cost)"
  type        = number
  default     = 1
}

variable "harden_compute" {
  description = "Set false to drop IMDSv2 and root volume encryption (trips baseline/compute)"
  type        = bool
  default     = true
}
