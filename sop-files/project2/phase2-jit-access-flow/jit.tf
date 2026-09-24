# Chain A, Project 2 (Just-in-Time Access and Confused Deputy Hardening).
#
# Deliverable 2: a real, working just-in-time access flow, replacing the
# standing developer role with something requested, justified and
# time-bound.
#
# The flow, end to end:
#
#   operator --(lambda:InvokeFunction)--> broker --(sts:AssumeRole)--> JIT role
#                                            |
#                                            +--(ssm:PutParameter)--> credential
#
# Three properties matter here, and each is enforced at a point the code
# cannot reach around:
#
#   1. Only the named requester may invoke the broker. That is the
#      function's resource policy, evaluated by IAM before the handler
#      runs. The handler does not decide who may ask, and could not be
#      tricked into deciding wrongly, because it is never asked.
#   2. A session is fifteen minutes long. The broker asks STS for 900
#      seconds and every credential it issues carries that expiry. The
#      ceiling itself lives in the broker's request, not on the role -
#      IAM rejects a role with max_session_duration below 3600, so an
#      hour is the tightest structural cap a role can carry. See the
#      note on the role below; the walkthrough's expiry phase proves
#      this by using a credential after its window rather than by
#      pointing at configuration.
#   3. Only the broker may assume the JIT role. Its trust policy names
#      the broker's role and nothing else, so the requester cannot skip
#      the flow - no justification, no record - and assume it directly.
#      The walkthrough tests that by attempting it, rather than
#      asserting it.
#
# The standing role being replaced is deliberately left untouched by
# this file. It is removed in deliverable 4's work, once this flow is
# proven, so that a working alternative exists before the old path
# closes. Ordering is the whole of that decision.

locals {
  jit_role_name        = "${var.environment_name}-jit-developer-access"
  jit_broker_role_name = "${var.environment_name}-jit-broker-role"
  jit_ssm_parameter    = "/${var.environment_name}/jit/session"

  # Built from names rather than from resource attributes on purpose.
  # The JIT role's trust policy names the broker's role, and the
  # broker's policy names the JIT role, so referring to each other by
  # attribute would give Terraform a dependency cycle to resolve and no
  # way to resolve it. Composing the ARN from the account ID and the
  # name we already chose keeps both resources independent.
  jit_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.jit_role_name}"
  jit_broker_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.jit_broker_role_name}"
}

# The role that replaces standing access.
#
# Same breadth as the role it replaces, deliberately. This project is
# not about making the permission smaller - Project 1 did that for the
# workload, and doing it again here would tangle two changes together
# and make the next phase harder to read. The change is that the
# permission is no longer permanent.
#
# max_session_duration is 3600, the shortest IAM will accept - and that
# is worth stating precisely, because the obvious assumption is wrong.
# The AssumeRole API accepts a DurationSeconds of 900, but an IAM role's
# max_session_duration must be between 3600 and 43200. A role therefore
# cannot be configured to refuse anything longer than fifteen minutes;
# an hour is the tightest structural ceiling available.
#
# So the fifteen-minute property belongs to the flow, not to the role:
# the broker requests 900 seconds and that is what bounds a session in
# practice, while 3600 bounds what any direct assumption could ever
# reach even if the broker were replaced. It is a real limit and a
# weaker one than it first looks, which is exactly the kind of thing
# this walkthrough exists to separate - a number in a configuration
# file is not the same as a control, unless something enforces it.
resource "aws_iam_role" "jit_developer_access" {
  name                 = local.jit_role_name
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = local.jit_broker_role_arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jit_developer_access_policy" {
  role       = aws_iam_role.jit_developer_access.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role" "jit_broker" {
  name = local.jit_broker_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Two permissions, both narrow. The broker may assume exactly one role,
# and may write exactly one parameter. It cannot read the parameter back
# - nothing in the flow needs it to - and it cannot assume the standing
# role, or any other.
data "aws_iam_policy_document" "jit_broker" {
  statement {
    sid       = "AssumeTheJitRoleOnly"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [local.jit_role_arn]
  }

  statement {
    sid       = "PublishTheRequestedCredential"
    effect    = "Allow"
    actions   = ["ssm:PutParameter"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.jit_ssm_parameter}"]
  }
}

resource "aws_iam_policy" "jit_broker" {
  name        = "${var.environment_name}-jit-broker"
  description = "Lets the JIT broker assume the JIT role and publish the credential it issues."

  policy = data.aws_iam_policy_document.jit_broker.json
}

resource "aws_iam_role_policy_attachment" "jit_broker" {
  role       = aws_iam_role.jit_broker.name
  policy_arn = aws_iam_policy.jit_broker.arn
}

resource "aws_iam_role_policy_attachment" "jit_broker_basic_logs" {
  role       = aws_iam_role.jit_broker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "jit_broker" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/jit_broker"
  output_path = "${path.module}/build/jit_broker.zip"
}

resource "aws_s3_object" "jit_broker_package" {
  bucket = aws_s3_bucket.lambda_artifacts.id
  key    = "jit_broker/${data.archive_file.jit_broker.output_md5}.zip"
  source = data.archive_file.jit_broker.output_path
  etag   = data.archive_file.jit_broker.output_md5
}

resource "aws_cloudwatch_log_group" "jit_broker" {
  name              = "/aws/lambda/${var.environment_name}-jit-broker"
  retention_in_days = 14
}

# Deliberately NOT attached to the VPC, unlike process_upload.
#
# This environment has no NAT gateway and only the free S3 gateway
# endpoint, both deliberate free-tier choices. A function inside this
# VPC therefore has no route to STS or SSM, which are public endpoints
# with no gateway form - reaching them would need interface endpoints,
# which bill by the hour and are the exact resource this environment
# avoids. The broker needs both services, so it runs outside the VPC and
# reaches them over the public endpoint as any other AWS API client
# would.
resource "aws_lambda_function" "jit_broker" {
  function_name = "${var.environment_name}-jit-broker"
  role          = aws_iam_role.jit_broker.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  s3_bucket = aws_s3_bucket.lambda_artifacts.id
  s3_key    = aws_s3_object.jit_broker_package.key

  source_code_hash = data.archive_file.jit_broker.output_base64sha256

  environment {
    variables = {
      JIT_ROLE_ARN       = local.jit_role_arn
      SSM_PARAMETER_NAME = local.jit_ssm_parameter
    }
  }

  depends_on = [aws_cloudwatch_log_group.jit_broker]
}

# The allowlist.
#
# One principal is named, and it is the operator. Nobody else in the
# account can invoke this function, whatever policy they carry - an
# explicit Allow in a resource policy is what makes a cross-principal
# call succeed, so its absence is a denial regardless of the caller's
# own permissions. That is the request step: a request exists only if
# this named principal made it, and every request is recorded by
# CloudTrail as a lambda:InvokeFunction call naming who made it, and by
# the function's own logs carrying the justification.
resource "aws_lambda_permission" "jit_broker_requester" {
  statement_id  = "AllowNamedRequesterToRequestAccess"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jit_broker.function_name
  principal     = var.jit_requester_principal
}

# Where the issued credential waits for its requester.
#
# SecureString, encrypted with the account's default SSM key rather than
# the CloudGuard KMS key - that key carries a deliberately over-broad
# policy belonging to another chain's project, and coupling this flow to
# it would put a second project's finding in the path of this one.
#
# The value is managed by the broker at runtime, so Terraform must not
# fight it: without ignore_changes the next plan would show the live
# credential as drift and offer to replace it with the placeholder,
# which would break a session that is legitimately in use.
resource "aws_ssm_parameter" "jit_session" {
  name        = local.jit_ssm_parameter
  description = "Most recent credential issued by the JIT broker, in credentials-file form. Overwritten on every granted request."
  type        = "SecureString"
  value       = "no session has been requested yet"

  lifecycle {
    ignore_changes = [value]
  }
}
