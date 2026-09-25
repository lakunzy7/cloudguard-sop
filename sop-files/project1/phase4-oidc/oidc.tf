# Workload identity federation, added by Chain A, Project 1, Phase 4.
#
# Everything else in this configuration is deployed from a machine
# holding a static access key. This file removes that requirement:
# GitHub Actions proves who it is with a short-lived OIDC token, and AWS
# exchanges that token for temporary credentials. There is no long-lived
# key to leak, rotate, discover in a backup, or forget existed.

# GitHub's OIDC provider. One per account, shared by every GitHub
# repository in the world.
#
# The thumbprint is effectively vestigial: AWS validates well-known
# providers like this one against its own certificate trust store, and
# the value below is the one GitHub's chain has used since 2023. The API
# still requires a value, which is why it is here.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# THE SECURITY BOUNDARY OF THIS FILE.
#
# A role GitHub Actions can assume is only as safe as what is permitted
# to assume it. Both conditions below matter, and the second one is the
# one people get wrong.
#
#   aud pins the token to AWS's STS audience, so an OIDC token GitHub
#   minted for some other relying party cannot be replayed here.
#
#   sub pins this to one repository and one branch. This is the
#   condition that stops every other GitHub repository on the internet
#   from assuming this role. The OIDC provider above is shared by all of
#   GitHub, so without a sub condition any repository anywhere could
#   mint a token AWS would accept — a mistake common enough to have its
#   own write-up, and the same class of problem Chain A, Project 2
#   examines in cross-account trust.
#
# Using StringEquals rather than StringLike deliberately: no wildcard in
# the subject means no other branch, tag, or pull request can match it.
#
# ---------------------------------------------------------------------
# THE sub VALUE BELOW, AND WHY IT LOOKS LIKE THAT
#
# GitHub does NOT send repo:OWNER/REPO:ref:... in this claim, which is
# what the AWS documentation and every tutorial show. It sends the owner
# and repository names with their immutable numeric IDs appended:
#
#   repo:<owner>@<ownerID>/<repo>@<repoID>:ref:refs/heads/main
#
# That was established in this project's first run by decoding the token
# the workflow minted, after a StringEquals against the documented form
# failed with a generic "not authorized" that named no claim at all. No
# amount of re-reading the trust policy would have revealed why.
#
# The IDs are the point rather than an inconvenience. Names are mutable:
# a repository can be renamed, and a deleted name can be re-registered
# by somebody else. A name-only condition would then trust whatever
# repository next held that name. The IDs cannot change, so this matches
# one specific repository for as long as it exists.
#
# This run works from a FORK of the upstream project repository:
#
#   upstream : expadox/cloudguard      (owner ID 289155627, repo ID 1333448283)
#   fork     : lakunzy7/cloudguard     (owner ID 47754154,  repo ID 1378228425)
#
# The fork is a different repository with a different ID, so the
# upstream's sub value would not match a workflow running here. Both IDs
# were read from the GitHub API before this file was written, which is
# why the value below could be filled in correctly first time rather
# than discovered through a failed workflow. It is still verified by
# decoding the token the workflow actually mints — see section 4.4 —
# because the whole lesson of the first run was not to trust the format.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    sid     = "AllowGitHubActionsOnMainOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # ⚠️ CHANGE THIS: the owner and repository IDs of the repository
      # you will run the workflow in.
      #
      # The two numbers are GitHub's immutable IDs, not names, and they
      # cannot be guessed — two API calls in the README read them for
      # you. Do not write this from GitHub's documentation: the
      # documented form of this claim, repo:OWNER/REPO:ref:..., never
      # matches, and the failure is a generic "not authorized" that
      # names no claim at all.
      values   = ["repo:lakunzy7@47754154/cloudguard@1378228425:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name        = "${var.environment_name}-github-actions-deploy"
  description = "Assumed by GitHub Actions via OIDC to deploy CloudGuard. No static key involved."

  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
}

# Permissions for the deploy role.
#
# Scoped to the services this environment actually uses rather than
# attached to AdministratorAccess. That is a real narrowing — a
# compromised workflow cannot reach services CloudGuard never touches —
# but be honest about its limit rather than overselling it: iam:* is
# administrator-equivalent in practice, because a principal that can
# create a role can create one with any permissions and then assume it.
#
# So the trust policy above is the control doing the real work, and this
# policy bounds the blast radius rather than eliminating it.
# Right-sizing a deploy role properly is a project of its own, and not
# the one this project is teaching.
data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid    = "ManageCloudGuardServices"
    effect = "Allow"

    actions = [
      "s3:*",
      "iam:*",
      "lambda:*",
      "kms:*",
      "ec2:*",
      "cloudtrail:*",
      "sns:*",
      "logs:*",
      "dynamodb:*",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "manage-cloudguard"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
