output "app_bucket" {
  description = "Name of the app bucket"
  value       = aws_s3_bucket.app.bucket
}

output "logs_bucket" {
  description = "Name of the logs bucket (null when create_logs_bucket is false)"
  value       = one(aws_s3_bucket.logs[*].bucket)
}

output "instance_ids" {
  description = "EC2 instance ids"
  value       = aws_instance.app[*].id
}
