data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  base_name = "${var.name_prefix}-${var.environment}"

  common_tags = {
    Demo      = "policies-as-code"
    ManagedBy = "env0"
  }

  required_tags = {
    Owner       = var.owner
    CostCenter  = var.cost_center
    Environment = var.environment
  }

  tags = var.include_required_tags ? merge(local.common_tags, local.required_tags) : local.common_tags
}

# ---------------------------------------------------------------------------
# S3. Policy: no public ACLs, public access block stays on, required tags.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "app" {
  bucket = "${local.base_name}-app-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

resource "aws_s3_bucket_ownership_controls" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "app" {
  bucket = aws_s3_bucket.app.id
  acl    = var.bucket_acl

  depends_on = [
    aws_s3_bucket_ownership_controls.app,
    aws_s3_bucket_public_access_block.app,
  ]
}

# Toggle create_logs_bucket to false after a deploy to get a "delete" in the plan.
resource "aws_s3_bucket" "logs" {
  count  = var.create_logs_bucket ? 1 : 0
  bucket = "${local.base_name}-logs-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

# ---------------------------------------------------------------------------
# Network. Policy: SSH/RDP never open to the internet (HTTPS is fine).
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name_prefix = "${local.base_name}-app-"
  description = "Policies as code demo security group"
  vpc_id      = data.aws_vpc.default.id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH"
  cidr_ipv4         = var.ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# Compute. Policy: approved instance types, IMDSv2, encrypted root volume,
# plus the cost thresholds in policy_data.json.
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  count = var.instance_count

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = var.harden_compute ? "required" : "optional"
  }

  root_block_device {
    encrypted   = var.harden_compute
    volume_type = "gp3"
    volume_size = 8
  }

  tags = merge(local.tags, { Name = "${local.base_name}-app-${count.index}" })
}
