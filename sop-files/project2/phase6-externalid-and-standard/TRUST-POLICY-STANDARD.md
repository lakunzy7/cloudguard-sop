# CloudGuard trust-policy standard

Every IAM role in this environment is measured against the four requirements
below. They are written to be checked rather than agreed with: each one names
the thing to look at in a trust policy and the condition that has to hold.

This is the standard referred to by Chain A, Project 2's deliverable 8, and it
is the thing Project 2's deliverable 9 audits the environment against. It was
written after the work rather than before it, and every rule in it comes from
something that project demonstrated rather than something that sounded right.

**Scope.** Trust policies, not permissions. What a role can *do* once assumed is
a separate question, and in this environment it belongs to whichever project
owns that role's permissions.

---

## 1. A cross-account trust must carry an ExternalId

**The rule.** If a trust policy names a principal in a different AWS account,
its `Allow` statement must carry:

```json
"Condition": { "StringEquals": { "sts:ExternalId": "<a value the caller must know>" } }
```

**Why.** Naming another account establishes *which account is calling* and
nothing else. In a multi-tenant relationship the vendor is one account serving
many customers, and the trust policy has no way to tell which customer the
vendor is acting for on any given call. That is the confused deputy: the vendor
is authorised to act and cannot prove who it acts for, so anything that can
steer the vendor can steer it into this account's role.

**How to check.** Read the `Principal`. If any entry is an account ARN outside
this account, the statement must have the condition above. The value must not
be guessable from anything public, and it must not be the account ID, the role
name, or the vendor's own name.

**The caveat, stated rather than hidden.** An ExternalId in this repository is
readable by anyone holding `iam:GetRole` on the role. In a real two-account
relationship it is a secret the vendor holds and the attacker does not see; here
it is demonstrated, and the demonstration is weaker than the practice for that
reason alone.

---

## 2. A role a human can assume must require MFA

**The rule.** If a trust policy allows an IAM user, or the root of this account,
to assume the role, its `Allow` statement must carry:

```json
"Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
```

**Why.** `aws:MultiFactorAuthPresent` describes the *session*, not the user, and
this is where it is easy to be deceived: a role can have a perfect MFA condition
and still be assumable without MFA by anyone who simply never presented any. The
condition is only load-bearing if the identity on the other side holds a device
that can satisfy it — which is why attaching the device is a prerequisite of the
work, not an afterthought.

**How to check.** Read the `Principal`. A `:root` entry for this account, or any
IAM user ARN, makes the role human-assumable and requires the condition. A role
whose only principals are roles or service principals is a machine path and does
not.

---

## 3. A same-account trust must not name the account root

**The rule.** A trust policy must not list this account's own root ARN as a
principal.

**Why.** `arn:aws:iam::<this-account>:root` in a trust policy does not mean the
root user. It means *every principal in this account* — and whether each of them
may actually assume the role is then decided somewhere else, in policies the
trust policy does not mention and a reader of it cannot see. The role being
replaced by Project 2 was built this way: broad, permanent, and assumable by
anything in the account that could present MFA.

**How to check.** Search the `Principal` for this account's root ARN. If it is
there, the trust is not scoped, whatever conditions sit alongside it.

**Interaction with rule 1.** A *cross-account* root principal is a different
case and is allowed — you often cannot know a vendor's role ARNs in advance.
That is precisely why rule 1 exists, and why the two rules are read together
rather than separately.

---

## 4. A federated trust must pin the subject, not just the issuer

**The rule.** A trust policy naming an OIDC or SAML provider must constrain
which identity at that provider may assume the role — for GitHub, a `sub`
condition — and must not rely on the issuer alone.

**Why.** Trusting the issuer trusts every identity it serves. For GitHub that is
every repository on the platform; for a SAML provider it is every user in the
directory. The issuer is not the principal.

**How to check.** The statement must carry a `StringEquals` or `StringLike`
condition on `sub` (or the SAML equivalent), naming the specific repository,
branch, or subject allowed. Note the trap this project already recorded: GitHub's
documented `sub` format never matches. The real value appends the immutable
numeric owner and repository IDs — `repo:OWNER@<ownerID>/REPO@<repoID>:ref:...` —
and a condition written from the documentation alone fails with a generic error
that names no claim.

---

## What is deliberately not in this standard

**A restriction on breadth of permissions.** It would be reasonable to expect
one, and it is not here on purpose. `cloudguard-jit-developer-access` carries
`PowerUserAccess`: broad, and correct for what it is, because the control that
makes it safe is that it expires. Writing a rule that forbade broad permissions
would flag the role this project built as the *improvement*, which is a sign the
rule was about the wrong thing. Least privilege and time-bound access are two
different controls, and this standard is about the boundary, not the contents.

**A rule about service principals.** `lambda.amazonaws.com` and its equivalents
appear in legitimate trust policies throughout this environment. The confused
deputy applies to services too — an S3 bucket can be configured by one account
to invoke a function in another — but the fix there is `SourceArn` or
`SourceAccount` rather than ExternalId, and it is a different piece of work.

**Anything about users.** Project 2's deliverable 9 audits roles. This account
holds IAM users whose access is not governed by a trust policy at all, and a
standard that appeared to cover them without covering them would be worse than
one that says so.

---

## How this is applied

Each role is checked against rules 1–4 by reading its trust policy, and the
result is recorded as it stands — including where a rule does not apply, and
including where a role fails. Project 2's audit is the first application, and it
covers every role in the account rather than only the ones that project created.
