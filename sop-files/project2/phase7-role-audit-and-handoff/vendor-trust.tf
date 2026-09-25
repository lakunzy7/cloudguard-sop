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
# One role, and it is the one the brief describes:
#
#   cloudguard-vendor-integration   the role the vendor assumes. Its trust
#                                   policy names the vendor's account and
#                                   requires an ExternalId.
#
# ---------------------------------------------------------------------
# WHAT WAS HERE, AND WHY IT IS NOT
# ---------------------------------------------------------------------
#
# A second role, cloudguard-vendor-deputy, stood here for most of this
# project. It was a stand-in for the vendor's own service role, created
# because the vendor's account is real but unreachable from here:
# 637739132594 is a second member account in the Expadox organization,
# and we hold no credentials in it.
#
# That model bought real evidence. A real principal assumed a real role
# under a real trust policy, was allowed while the policy carried no
# condition, and was refused once one was added. Nothing in that chain
# was simulated, and Phases 5 and 6 of the walkthrough are the record.
#
# It cost one honest limitation, stated in the walkthrough rather than
# left for a reader to infer: an attack across the account boundary was
# never demonstrated, because we could not stand on the other side of it.
#
# The deputy is gone, and Phase 7's audit is why. Applying the standard in
# TRUST-POLICY-STANDARD.md to every role in this account found it failing
# rule 2 - a role a human can assume, with no MFA condition. The finding
# was right, and right about something more important than the rule: the
# deputy was scaffolding. In production the role it models lives in the
# vendor's account, and keeping a copy here meant keeping a role whose
# whole purpose was to hold standing permission to assume ours.
#
# Removing it also returns this file to the shape deliverable 5 asked
# for: one principal, a real second account, one condition. Anyone
# wanting to repeat Phases 5 and 6 can restore the deputy from the
# walkthrough's companion repository. Scaffolding does not need to be
# permanent to be reproducible.

locals {
  vendor_integration_name = "${var.environment_name}-vendor-integration"
}

# The role the vendor assumes. Deliverable 5's artifact.
#
# One principal: the vendor's account, 637739132594, a real second account
# in the organization. That is what a production integration looks like
# when a vendor's role ARNs are not known in advance, and it is why the
# condition below is not optional - naming an account establishes who is
# calling and nothing about which of that account's concerns they are
# calling for.
#
# The Condition is the whole of Phase 6, and it is worth being precise
# about what it adds. The statement already establishes who is
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
          AWS = "arn:aws:iam::${var.vendor_account_id}:root"
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

# The deputy that stood here is recorded at the top of this file. Its
# removal is Phase 7's, and it is deliberate: the audit found it failing
# rule 2, and the audit was right for a reason the rule only gestured at.
