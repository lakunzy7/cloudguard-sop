# CloudGuard — SOP files

Source files for the CloudGuard walkthrough (Chain A, Project 1).

The walkthrough teaches least-privilege IAM and workload identity
federation by having you build the changes yourself, step by step. Some
of those steps produce a file too large to print in the guide without
burying the lesson — this repository holds those files, so each step can
show a single copy command instead of a hundred lines of Terraform.

## How to use it

Clone this alongside the environment:

```bash
git clone https://github.com/lakunzy7/cloudguard-sop.git
```

Then, whenever the walkthrough reaches a step that says a file is
provided here, copy it into place. For example, section 4.2:

```bash
cp cloudguard-sop/sop-files/phase4-oidc/oidc.tf terraform/oidc.tf
```

The walkthrough always names the exact command. Nothing here needs to be
typed by hand.

## What is here, and when it is used

| File | Walkthrough section | What it is |
|---|---|---|
| `sop-files/phase2-cloudtrail/cloudtrail.tf` | 2.3 | The trail with an S3 data-event selector added. Data events are off by default on every trail; without this, CloudTrail cannot see a single `GetObject` or `PutObject`, and the analysis the project depends on has nothing to read. |
| `sop-files/phase3-rightsizing/iam.tf` | 3.2 | The right-sized policy replacing `AmazonS3FullAccess`. Two statements: `s3:GetObject` on the bucket, `s3:PutObject` on `metadata/*`. |
| `sop-files/phase4-oidc/providers.tf` | 4.1.2 | The same provider configuration with an S3 remote backend added, so a GitHub Actions runner can read the state a CI deploy needs. |
| `sop-files/phase4-oidc/oidc.tf` | 4.2 | The GitHub OIDC provider, the deploy role, and the trust policy that stops every other repository on GitHub assuming it. |
| `sop-files/phase5-drift/check-policy-drift.sh` | 5.3 | The drift check itself. Resolves the live policy, reads real CloudTrail usage for a lookback window, and compares the two in both directions. |
| `sop-files/phase5-drift/policy-drift-check.yml` | 5.3 | The schedule. `cron: '17 6 * * 1'` — Mondays at 06:17 UTC — running the script through the same OIDC role Phase 4 created. |

## ⚠️ What you must change before these will work for you

**Three values in these files are specific to the author's account and
repository. They will not work in yours.** Each is marked in the file
with a `CHANGE THIS` comment.

| File | The value | What it must become |
|---|---|---|
| `phase4-oidc/providers.tf` | `cloudguard-tfstate-113410693155` | Your own state bucket name |
| `phase4-oidc/oidc.tf` | the `sub` condition value | The IDs of the repository you will run the workflow in |
| `phase4-oidc/terraform-deploy.yml` | `arn:aws:iam::113410693155:role/...` | Your account's role ARN |
| `phase5-drift/check-policy-drift.sh` | the `POLICY_ARN` and `TRAIL_BUCKET` defaults | Your account ID in both |
| `phase5-drift/policy-drift-check.yml` | `arn:aws:iam::113410693155:role/...` | Your account's role ARN |

Everything else in these files is account-independent. Bucket names
everywhere else in the environment are built with
`${data.aws_caller_identity.current.account_id}`, so Terraform derives
them from whichever account it runs in and they need no editing.

### Finding your AWS account ID

```bash
aws sts get-caller-identity --query Account --output text
```

Use it to build both the state bucket name, `cloudguard-tfstate-<account-id>`,
and the role ARN, `arn:aws:iam::<account-id>:role/cloudguard-github-actions-deploy`.

### Finding the repository's owner and repository IDs

**First, decide which repository you will run the workflow in.** This is
the one step in the walkthrough that needs a repository of your own.
Phases 1 to 3 work from a plain clone of the upstream environment, but a
GitHub Actions workflow has to live somewhere, and the OIDC token is
bound to the repository that mints it — so from section 4.3 onward you
need somewhere to push.

Either of these gives you one:

```bash
gh repo fork expadox/cloudguard --clone=false
```

```bash
gh repo create <your-username>/cloudguard --public --source=. --push
```

The `sub` condition needs two **immutable numeric** identifiers for that
repository, not the names. Get them from the GitHub API:

```bash
gh api users/<your-username> --jq '.id'
```

```bash
gh api repos/<your-username>/cloudguard --jq '.id'
```

Then assemble the string:

```
repo:<username>@<ownerID>/cloudguard@<repoID>:ref:refs/heads/main
```

For the author's repository that is `lakunzy7@47754154` and
`1378228425`, which is where the value in `oidc.tf` comes from. Yours
will be different numbers, because it is a different repository.

**Why the numbers rather than just the names.** Names are mutable — a
repository can be renamed, and a deleted name can be re-registered by
somebody else. A condition matching on names alone would then trust
whatever repository next held that name, including one an attacker
created. The numeric IDs cannot change, so the condition matches one
specific repository for as long as it exists.

**And a warning worth believing.** GitHub's own documentation shows this
claim in the form `repo:OWNER/REPO:ref:...`, **which never matches**. The
real value appends the numeric IDs as shown above. This was established
by decoding the token the workflow actually mints, after a condition
written from the documentation failed with a generic "not authorized"
that named no claim at all. If you write it from the docs, it will not
work.

## Two things worth understanding before copying

**These are the files at the end of their phase, not the end of the
project.** `iam.tf` is provided once, at section 3.2, in its right-sized
form. Section 3.4 then has you deliberately break it and repair it, and
that test is the point of the phase — copying the file again would skip
it.

**Some steps are intentionally not here.** Small edits are shown inline
in the walkthrough, because a copy command hides *what changed*, and the
change is usually the lesson. If a step needs you to add four lines to a
file you already have, the guide shows you those four lines and where
they go.

## Related

The environment these files belong to is deployed from the upstream
project repository. This repository holds only the walkthrough's source
files — it is not a copy of the environment, and it contains no
credentials, no state, and nothing account-specific.
