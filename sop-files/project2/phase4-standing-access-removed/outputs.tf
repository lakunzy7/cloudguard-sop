output "uploads_bucket_name" {
  value = aws_s3_bucket.uploads.id
}

output "legacy_exports_bucket_name" {
  value       = aws_s3_bucket.legacy_exports.id
  description = "The bucket containing Project 5's seeded DSPM finding."
}

output "lambda_function_name" {
  value = aws_lambda_function.process_upload.function_name
}

output "lambda_role_name" {
  value       = aws_iam_role.lambda_process_upload.name
  description = "The over-permissioned role Project 1 right-sizes."
}

output "kms_key_id" {
  value       = aws_kms_key.uploads_encryption.key_id
  description = "The key with the seeded overly-broad key policy for Project 6."
}

output "security_group_id" {
  value       = aws_security_group.lambda_process_upload.id
  description = "The security group with the seeded unrestricted egress rule for Project 6."
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail_logs.id
}

output "sns_alerts_topic_arn" {
  value = aws_sns_topic.security_alerts.arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}
