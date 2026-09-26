# Chain A, Project 3 (CIEM and IAM Chaos Engineering), deliverable 8.
#
# A trust-maintenance role for the deployment pipeline. It reads role
# configuration and keeps the CI role's trust relationship current when the
# repository or branch it federates from changes.
#
# Almost all of it is read-only. The single write is scoped to one role, which
# is what makes this worth a graph rather than a glance: that role holds
# `iam:*` on everything, so the ability to rewrite its trust document is the
# ability to become it. Nothing in this file is marked as a seed, because a
# seeded path that announces itself would not test the analysis.
#
# This is the file as it is applied in section 7.1. Section 7.3 removes the
# `MaintainTheDeployRoleTrust` statement and nothing else, and section 7.5
# deletes the file entirely to leave the account as found.

locals {
  seeded_trust_role_name = "${var.environment_name}-trust-automation-role"
}

resource "aws_iam_role" "seeded_trust_automation" {
  name = local.seeded_trust_role_name

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

data "aws_iam_policy_document" "seeded_trust_automation" {
  # The part that reads as the whole role.
  statement {
    sid    = "ReadRoleConfiguration"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoles",
    ]
    resources = ["*"]
  }

  # The part that is the escalation.
  statement {
    sid       = "MaintainTheDeployRoleTrust"
    effect    = "Allow"
    actions   = ["iam:UpdateAssumeRolePolicy"]
    resources = [aws_iam_role.github_actions_deploy.arn]
  }
}

resource "aws_iam_policy" "seeded_trust_automation" {
  name        = "${var.environment_name}-trust-automation"
  description = "Lets the trust-automation role inspect role configuration and maintain the deploy role's trust."

  policy = data.aws_iam_policy_document.seeded_trust_automation.json
}

resource "aws_iam_role_policy_attachment" "seeded_trust_automation" {
  role       = aws_iam_role.seeded_trust_automation.name
  policy_arn = aws_iam_policy.seeded_trust_automation.arn
}
