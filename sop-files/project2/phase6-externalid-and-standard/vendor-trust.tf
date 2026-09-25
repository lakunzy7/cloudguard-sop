# Chain A, Project 2 (Just-in-Time Access and Confused Deputy Hardening).
#
# Deliverables 5 and 6: a real cross-account trust relationship, and the
# confused deputy risk demonstrated against it concretely.
#
# The scenario: a vendor integrates with CloudGuard. To work with
# CloudGuard's uploads, the vendor's service assumes a role in this
# account. Nothing about that is unusual - it is how most third-party
# integrations work - and it is exactly the shape of trust that goes
# wrong when it is built with no ExternalId.
#
# Two roles:
#
#   cloudguard-vendor-integration   the role the vendor assumes. Its trust
#                                   policy names the vendor's account and,
#                                   at this stage, carries no condition.
#                                   This is deliverable 5.
#
#   cloudguard-vendor-deputy        a stand-in for the vendor's service
#                                   role. It holds standing permission to
#                                   assume the integration role, and that
#                                   permission is the thing that gets
#                                   confused.
#
# ---------------------------------------------------------------------
# WHY THE DEPUTY LIVES IN THIS ACCOUNT, AND WHAT THAT COSTS THE EVIDENCE
# ---------------------------------------------------------------------
#
# The vendor's account is real. 637739132594 is a second member account
# in the Expadox organization, and the account owner supplied it for
# exactly this purpose. What is not real is our ability to hold
# credentials there, so the vendor's side of the trust is modelled by a
# role in this account.
#
# What that buys: the mechanism is demonstrated with real calls. A real
# principal assumes a real role under a real trust policy, is really
# allowed while the policy carries no condition, and is really refused
# once one is added. Nothing in that chain is simulated.
#
# What it costs: an attack across the account boundary is not
# demonstrated, because we cannot stand on the other side of it. The
# walkthrough states this rather than letting a reader infer more than
# the evidence supports.
#
# The alternative was to construct the cross-account role and argue the
# risk from documentation. That produces a true statement and no
# evidence, which is the trade this project declines everywhere else.

locals {
  vendor_deputy_name      = "${var.environment_name}-vendor-deputy"
  vendor_integration_name = "${var.environment_name}-vendor-integration"

  # Composed from names rather than resource attributes, for the same
  # reason terraform/jit.tf does it: the deputy's policy names the
  # integration role and the integration role's trust names the deputy,
  # so referring to each other by attribute would give Terraform a
  # dependency cycle with no way to break it.
  vendor_deputy_arn      = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.vendor_deputy_name}"
  vendor_integration_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.vendor_integration_name}"
}

# The role the vendor assumes. Deliverable 5's artifact.
#
# Two principals, and the difference between them is the whole of this
# phase:
#
#   the vendor's account   637739132594, a real second account. In a
#                          production integration this would be the only
#                          principal here, and the trust would be genuine
#                          in both directions.
#
#   the deputy             the model described above, present so that the
#                          risk can be demonstrated from an account we
#                          can actually act in.
#
# The Condition below is the whole of Phase 6, and it is worth being
# precise about what it adds. The statement already establishes who is
# calling. It says nothing about which of the vendor's customers they are
# calling for, and without the condition below there is nothing in the
# request that could say - which is the gap Phase 5 demonstrates.
#
# StringEquals on sts:ExternalId closes it by requiring a value the
# caller has to know and cannot guess. An attacker who can steer the
# vendor's service can still make it call, but cannot make it call with a
# secret it does not hold for this integration.
resource "aws_iam_role" "vendor_integration" {
  name = local.vendor_integration_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.vendor_account_id}:root",
            local.vendor_deputy_arn,
          ]
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.vendor_external_id
          }
        }
      }
    ]
  })
}

# What the vendor gets once it is in. Scoped to the bucket the
# integration exists to read, and to reading it - no writes, no other
# bucket, no account-wide listing. A role that is going to be assumed by
# a third party is not the place to be generous, and the temptation to
# be generous is strongest exactly where the trust is weakest.
data "aws_iam_policy_document" "vendor_integration" {
  statement {
    sid    = "ListTheUploadsBucket"
    effect = "Allow"

    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.uploads.arn]
  }

  statement {
    sid    = "ReadUploadedObjects"
    effect = "Allow"

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }
}

resource "aws_iam_policy" "vendor_integration" {
  name        = "${var.environment_name}-vendor-integration"
  description = "Read access to the uploads bucket, for the third-party integration in Project 2's cross-account scenario."

  policy = data.aws_iam_policy_document.vendor_integration.json
}

resource "aws_iam_role_policy_attachment" "vendor_integration" {
  role       = aws_iam_role.vendor_integration.name
  policy_arn = aws_iam_policy.vendor_integration.arn
}

# The deputy. A model of the vendor's service role, not a role the
# vendor would have in their own account.
#
# It is trusted by one principal only - the operator - rather than by the
# account, which matters: this project removed a role that any principal
# with MFA could assume, and reintroducing that shape here to serve a
# demonstration would be a poor trade.
#
# Note what the deputy is: a role holding standing permission to assume
# another account's roles. That is not a defect in it. It is the deputy's
# job, and it is what makes the deputy confusing - it cannot tell which
# customer it is acting for, because nothing in the request says.
resource "aws_iam_role" "vendor_deputy" {
  name = local.vendor_deputy_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.jit_requester_principal
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# The deputy's standing reach, and the only permission it carries.
#
# In a real vendor's account this policy would name every customer role
# the vendor is integrated with, because that is how a multi-tenant
# service works: one role, many customers, and the customer identified
# only by which role ARN it is asked to assume.
data "aws_iam_policy_document" "vendor_deputy" {
  statement {
    sid    = "AssumeCustomerIntegrationRoles"
    effect = "Allow"

    actions   = ["sts:AssumeRole"]
    resources = [local.vendor_integration_arn]
  }
}

resource "aws_iam_policy" "vendor_deputy" {
  name        = "${var.environment_name}-vendor-deputy"
  description = "Lets the modelled vendor service assume CloudGuard's integration role, as a vendor would for any customer."

  policy = data.aws_iam_policy_document.vendor_deputy.json
}

resource "aws_iam_role_policy_attachment" "vendor_deputy" {
  role       = aws_iam_role.vendor_deputy.name
  policy_arn = aws_iam_policy.vendor_deputy.arn
}
