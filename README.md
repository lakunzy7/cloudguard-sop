# CloudGuard — SOP files

Source files for the CloudGuard walkthroughs (Chain A, Projects 1 and 2).

One directory per project, and inside each, one directory per phase —
mirroring the walkthroughs, which are read a phase at a time.

The walkthroughs teach least-privilege IAM and workload identity
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
cp cloudguard-sop/sop-files/project1/phase4-oidc/oidc.tf terraform/oidc.tf
```

The walkthrough always names the exact command. Nothing here needs to be
typed by hand.

## Project 1 — Automated Least-Privilege and Workload Identity Federation

| File | Walkthrough section | What it is |
|---|---|---|
| `sop-files/project1/phase2-cloudtrail/cloudtrail.tf` | 2.3 | The trail with an S3 data-event selector added. Data events are off by default on every trail; without this, CloudTrail cannot see a single `GetObject` or `PutObject`, and the analysis the project depends on has nothing to read. |
| `sop-files/project1/phase3-rightsizing/iam.tf` | 3.2 | The right-sized policy replacing `AmazonS3FullAccess`. Two statements: `s3:GetObject` on the bucket, `s3:PutObject` on `metadata/*`. |
| `sop-files/project1/phase4-oidc/providers.tf` | 4.1.2 | The same provider configuration with an S3 remote backend added, so a GitHub Actions runner can read the state a CI deploy needs. |
| `sop-files/project1/phase4-oidc/oidc.tf` | 4.2 | The GitHub OIDC provider, the deploy role, and the trust policy that stops every other repository on GitHub assuming it. |
| `sop-files/project1/phase5-drift/check-policy-drift.sh` | 5.3 | The drift check itself. Resolves the live policy, reads real CloudTrail usage for a lookback window, and compares the two in both directions. |
| `sop-files/project1/phase5-drift/policy-drift-check.yml` | 5.3 | The schedule. `cron: '17 6 * * 1'` — Mondays at 06:17 UTC — running the script through the same OIDC role Phase 4 created. |

## Project 2 — Just-in-Time Access and Confused Deputy Hardening

Project 2 continues in the same environment as Project 1, so the same
clone works. If you already have it, pull before starting section 2.4:

```bash
cd cloudguard-sop
git pull
```

| File | Walkthrough section | What it is |
|---|---|---|
| `sop-files/project2/phase2-jit-access-flow/jit.tf` | 2.4 | The JIT role, the broker's role and its two permissions, the broker function, the resource policy that acts as the allowlist, and the SSM parameter the credential is published to. |
| `sop-files/project2/phase2-jit-access-flow/handler.py` | 2.4 | The broker itself. Requires a justification, assumes the JIT role for 900 seconds, writes the credential to SSM in credentials-file form, and returns a summary containing no credential at all. |
| `sop-files/project2/phase2-jit-access-flow/variables.tf` | 2.4 | The environment's variables file with one addition: `jit_requester_principal`, which is the allowlist. Section 2.4 also shows those four lines inline, so you can see what changed — this is here for anyone who would rather copy the result than retype it. |
| `sop-files/project2/phase4-standing-access-removed/iam.tf` | 4.2 | The role file **after** the standing developer role was deleted, with the closure record in its place. Staged because a deletion is the one change a description cannot convey exactly — there is no new text to read, only text that is gone. |
| `sop-files/project2/phase4-standing-access-removed/outputs.tf` | 4.2 | The outputs file with `standing_developer_role_arn` removed. It referenced the deleted role, and an output pointing at a resource that no longer exists fails the next plan rather than reporting anything useful. |
| `sop-files/project2/phase5-cross-account-trust/vendor-trust.tf` | 5.3 | The cross-account scenario: the role the vendor assumes, whose trust policy names a real second AWS account and carries no condition, and the deputy that stands in for the vendor's service. |
| `sop-files/project2/phase5-cross-account-trust/variables.tf` | 5.3 | The variables file again, one phase on. It now carries `vendor_account_id` alongside the allowlist principal. |

| `sop-files/project2/phase6-externalid-and-standard/vendor-trust.tf` | 6.1 | The same scenario role, now carrying the `sts:ExternalId` condition that closes the gap Phase 5 demonstrated. Diff it against the Phase 5 copy and the change is one block. |
| `sop-files/project2/phase6-externalid-and-standard/variables.tf` | 6.1 | The variables file one phase on again, now with `vendor_external_id`. |
| `sop-files/project2/phase6-externalid-and-standard/TRUST-POLICY-STANDARD.md` | 6.6 | The standard itself — four checkable requirements for every trust policy in this environment, each one derived from something this project demonstrated. |
| `sop-files/project2/phase7-role-audit-and-handoff/vendor-trust.tf` | 7.4 | The scenario role one last time, after the audit. The deputy is gone and the trust names only the real vendor account — which is the shape deliverable 5 described before a model was added to make it testable. |

**`variables.tf` appears three times, and that is deliberate.** Each copy
is the file at the end of *its* phase, so section 2.4 gets one with a
single addition, 5.3 gets one with two, and 6.1 gets one with three.
Copying a later file early would work — an unused variable costs nothing
— but it would put a variable in front of you that the phase you are in
has not explained yet.

**These are files whole, for changes that are small.** That is a
deliberate departure from the rule Project 1 follows below, where small
edits are shown inline and not staged. Both routes are given for
Project 2: the walkthrough prints the change so you can see *what*
changed, and the file is here so you can copy the result instead of
retyping it. A deletion has nothing to print, which is why Phase 4's two
files are staged with no inline equivalent beyond the description of what
went.

## Project 3 — CIEM and IAM Chaos Engineering

| File | Walkthrough section | What it is |
|---|---|---|
| `sop-files/project3/phase3-chaos-framework/IAM-CHAOS-FRAMEWORK.md` | 3.2 | The chaos framework: five rules, seven steps, the three ways a test lies to you, and the method applied to the tests Projects 1 to 3 actually ran. |

### ⚠️ What is deliberately *not* staged here, and why

**Phase 4 stages nothing, on purpose.** That phase runs a chaos test: it removes one permission, watches what breaks, and puts it back. The broken state is the *experiment*, not a deliverable — staging it would hand you a file whose only purpose is to break the environment, and copying it would do exactly that.

**The restore point is the repository.** `terraform/jit.tf` is under version control, so `git checkout terraform/jit.tf` returns it exactly as it was. That is stronger than a staged copy, because it cannot drift: the commit is the record. The walkthrough's Step 1 says so before anything is changed, which is the framework's own first rule — record the state before you disturb it.

The same applies to any future phase whose work is a reversible experiment rather than a file to keep. If you are looking here for something to copy and cannot find it, check whether the walkthrough is asking you to *do* something instead.

## ⚠️ What you must change before these will work for you

**A handful of values in these files are specific to the author's account
and repository. They will not work in yours.** Each is marked in the file
with a `CHANGE THIS` comment.

| File | The value | What it must become |
|---|---|---|
| `phase4-oidc/providers.tf` | `cloudguard-tfstate-113410693155` | Your own state bucket name |
| `phase4-oidc/oidc.tf` | the `sub` condition value | The IDs of the repository you will run the workflow in |
| `phase4-oidc/terraform-deploy.yml` | `arn:aws:iam::113410693155:role/...` | Your account's role ARN |
| `phase5-drift/check-policy-drift.sh` | the `POLICY_ARN` and `TRAIL_BUCKET` defaults | Your account ID in both |
| `phase5-drift/policy-drift-check.yml` | `arn:aws:iam::113410693155:role/...` | Your account's role ARN |
| `terraform/variables.tf` (Project 2) | the `jit_requester_principal` default | Your own operator identity, as an ARN — the one principal allowed to request just-in-time access |

**None of Project 2's staged files needs editing to work.** Every
account-specific value in them is either built from
`${data.aws_caller_identity.current.account_id}` or derived from
`var.environment_name`, so they deploy unchanged into any account. The
one value you do set — the allowlist principal — is named in the table
above, and it is a value only you can supply rather than something that
has to be corrected.

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
