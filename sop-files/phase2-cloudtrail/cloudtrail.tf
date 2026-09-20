# CloudTrail is not optional infrastructure in this environment, it is
# the actual data source Chain A, Project 1 needs to determine which
# permissions the over-permissioned Lambda role in iam.tf genuinely
# uses, and what Chain C, Project 9's custom detection engineering
# needs to tell normal behavior from anomalous behavior in the first
# place. An environment without a real trail would make both projects
# impossible to do honestly.

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "${var.environment_name}-cloudtrail-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.environment_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  # S3 object-level activity is recorded as DATA events, not management
  # events, and data events are off by default. Without this selector the
  # trail cannot see a single GetObject or PutObject, which means it
  # cannot answer the one question Chain A, Project 1 exists to ask: what
  # does the process_upload role actually do with S3?
  #
  # Scoped to the uploads bucket rather than the whole account, because
  # data events bill per event recorded and that bucket is the only one
  # this function touches. Widening it to arn:aws:s3::: would also pull
  # in every other identity in the account that happens to use S3, which
  # is noise the analysis does not need.
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.uploads.arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}
