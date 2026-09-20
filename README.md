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
