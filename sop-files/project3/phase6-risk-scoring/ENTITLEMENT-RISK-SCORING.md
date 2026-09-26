# CloudGuard entitlement risk scoring

Chain A, Project 3, deliverable 7. A method for ranking the principals in this
account by how much they actually expose it, and the ranking it produces.

The brief asks for *"a real, written methodology ranking CloudGuard's roles by
actual risk, combining blast radius, whether access is standing or JIT, and
escalation potential, producing a genuine prioritized list, not a flat
inventory."*

**The last clause is the hard one.** An inventory lists what exists; a ranking
says which of it matters. Anything that assigns a row to every role and calls
the result a score has restated the inventory in a different shape. So this
document has to be willing to say that some of these roles do not matter much,
and to put a number on that.

---

## The four dimensions

Each principal is scored 1–5 on four things. They are multiplied, not added,
because a total of 4 means something very different depending on whether it is
four ones or a single four — and only one of those is dangerous.

### Blast radius — what does holding this reach?

| Score | Meaning |
|---|---|
| 5 | Administrative, or able to become so. Effective control of the account |
| 4 | Broad service access across all resources of that service |
| 3 | Broad access within one service, or write access to shared data |
| 2 | Scoped access to named resources |
| 1 | A single action on a single resource |

### Persistence — how long does holding it last?

| Score | Meaning |
|---|---|
| 5 | Standing. Assumable at any time, indefinitely, by design |
| 4 | Standing, but gated by a condition that could be satisfied once and reused |
| 3 | Long-lived when obtained (hours), or refreshable without new approval |
| 2 | Time-bound and request-gated — minutes, and only on demand |
| 1 | Single-use, or bound to one invocation |

### Reachability — how easily can it be obtained?

| Score | Meaning |
|---|---|
| 5 | Any principal in the account, or anyone who compromises one credential |
| 4 | Any principal holding a device and a password |
| 3 | A specific role, or a class of principals |
| 2 | A specific principal, or a repository pinned by an immutable identifier |
| 1 | Requires a second party to act |

### Escalation — can it reach more than it appears to?

| Score | Meaning |
|---|---|
| 5 | `iam:*`, `iam:PassRole` with a compute service, or equivalent |
| 4 | Can modify a trust policy or attach policies |
| 3 | Can create a resource that runs as another identity |
| 2 | Can read credentials or secrets belonging to another principal |
| 1 | What you see is what you get |

**Where the scores come from.** Blast radius and escalation are read from the
policies. Persistence and reachability are read from the trust policy. All four
are checkable against the account, and the tables above are specific enough that
a reader can disagree with one number and re-run the arithmetic.

---

## The ranking

Scored on the state of the account after Projects 1, 2 and 3 had finished with
it. Sorted by the product.

| # | Principal | Blast | Persist | Reach | Escal | **Score** |
|---|---|---|---|---|---|---|
| 1 | the four IAM users | 5 | 5 | 4 | 5 | **500** |
| 2 | `OrganizationAccountAccessRole` | 5 | 5 | 3 | 5 | **375** |
| 3 | `cloudguard-github-actions-deploy` | 5 | 4 | 2 | 5 | **200** |
| 4 | `AWSReservedSSO_Billing_…` | 3 | 4 | 3 | 2 | **72** |
| 5 | `cloudguard-vendor-integration` | 2 | 5 | 3 | 2 | **60** |
| 6 | `cloudguard-jit-developer-access` | 4 | 2 | 2 | 3 | **48** |
| 7 | `cloudguard-jit-broker-role` | 2 | 3 | 2 | 3 | **36** |
| 8 | `cloudguard-process-upload-role` | 2 | 3 | 2 | 1 | **12** |

Sorted by the product, highest first. The scores are shown so that a reader who
disagrees with a number can re-run the arithmetic rather than having to argue
with the ordering.

---

## The reasoning, principal by principal

### 1. The four IAM users — 500

`cloudguard@deploy`, `lakunzy7`, `ogaziechi` and `Samuel` all hold
administrative permissions.

**Blast 5, Persist 5, Reach 4, Escal 5.** They score above every role because
they are everything a role is, permanently, with one extra property: **they
authenticate with long-lived credentials.** A role session expires; an access
key does not.

**Two of them have no MFA device** — `ogaziechi` and `Samuel`, established in
Phase 1 by PMapper and confirmed in the console. Two more, `cloudguard@deploy`
and `lakunzy7`, have access keys and can alter permissions without a second
factor.

**Why they appear in a document about roles.** The deliverable says *roles*, and
these are not roles. They are listed because a ranking that omitted the four
principals holding more standing access than anything it did rank would be
arithmetic in service of a blind spot. They are the top of this list, and the
reason is the same one Project 2 spent opening hours on: standing access is the
thing being removed, and these hold the most of it.

### 2. `OrganizationAccountAccessRole` — 375

**Blast 5.** `AdministratorAccess`.
**Persist 5.** Standing.
**Reach 3.** Assumable by any principal in the management account.
**Escal 5.** Unrestricted IAM.
**Last used: never.**

A cross-account administrative trust with no ExternalId, held open permanently,
by an account this project does not control, and never exercised. It is the
highest-scoring role here and the least able to be fixed: it is AWS's own,
created when this account joined the organization, and the organization's
tooling depends on it.

**It also inherits the revocability problem below in its worst form.** If
`sts:AssumeRole` on this role were removed, Phase 4 and 5 say the account would
likely keep honouring it — for a role that grants the management account
administrative access.

### 3. `cloudguard-github-actions-deploy` — 200

```json
{"Action": ["sns:*","s3:*","logs:*","lambda:*","kms:*","iam:*","ec2:*","dynamodb:*","cloudtrail:*"],
 "Resource": "*"}
```

**Blast 5.** `iam:*` on `*` is administrative in everything but name, and
`cloudtrail:*` means this principal can stop the account recording what it does.
That is the capability Project 1's organization guardrail existed to prevent, and
it is held here by the identity that runs on every push.

**Persist 4, not 5.** Standing in the sense that it can be assumed at any time,
but the trust policy pins the subject to one repository and branch by immutable
numeric ID. That condition cannot be satisfied by anyone else, so it is not
"assumable by anybody" — it is "assumable by anyone who can push to `main`."

**Reach 2.** Only that repository, only that branch.

**Escal 5.** It can create policies, attach them, and rewrite any trust policy
including its own.

**Why it ranks where it does.** Nothing here is a mistake — Terraform needs to
manage IAM, and the trust is pinned as tightly as Project 1 could pin it. But a
CI identity with `iam:*` and `cloudtrail:*` is the account's largest single
capability, and before this document nothing had said so. **It is not a defect;
it is a concentration**, and concentrations deserve to be named even when every
individual decision behind them was correct.

### 4. `AWSReservedSSO_Billing_…` — 72

**Blast 3, Persist 4, Reach 3, Escal 2.** A Billing permission set, federated
through the organization's identity provider.

Its trust policy carries `SAML:aud` and no subject condition, so rule 4 of
Project 2's standard flags it. The access decision lives in permission-set
assignments instead — a control the trust policy neither shows nor enforces.
Not fixable from here, and already documented in Project 2's audit.

### 5. `cloudguard-vendor-integration` — 60

**Blast 2, Persist 5, Reach 3, Escal 2.** Read access to one bucket, trusted by
a real second account, gated by an ExternalId.

It scores above the JIT role, which looks wrong until the persistence column is
read: nothing in this account can shorten or observe a session held in
`637739132594`. The ExternalId makes the trust safe; it does not make it
time-bound. **A cross-account trust is standing by nature, and this one is
standing correctly** — which is worth distinguishing from the standing grants
this project removed.

### 6. `cloudguard-jit-developer-access` — 48

**Blast 4.** `PowerUserAccess` — everything except IAM.
**Persist 2.** Fifteen minutes, on request, approver-recorded.
**Reach 2.** One role, the broker.
**Escal 3.** `PowerUserAccess` excludes `iam:PassRole`, which Phase 2 tested
directly; the remaining reach is through Lambda on roles already trusted.

**This is the highest-blast-radius role in the account that is not a mistake,
and it scores sixth.** That is the whole argument of Project 2 in one row: the
same breadth as the standing role it replaced, made safe not by being narrower
but by being temporary, single-principal and recorded. A ranking that scored it
alongside the role it replaced would have missed the only thing that changed.

### 7. `cloudguard-jit-broker-role` — 36

**Blast 2, Persist 3, Reach 2, Escal 3.** Assumes one role, writes one
parameter, runs outside the VPC. It is the mechanism, not the capability.

### 8. `cloudguard-process-upload-role` — 12

**Blast 2, Persist 3, Reach 2, Escal 1.** Two S3 actions on one bucket, scoped
in Project 1 from observed usage. The lowest score in the account, and it is
where Project 1 started.

---

## The dimension the brief does not name

The four dimensions above score how much access a principal holds and how
readily it can be obtained. **Project 3's own chaos test established a fifth
thing that applies to all of them: a permission that is removed does not
necessarily stop working.**

Phase 4 measured it at **not enforced within twenty-seven minutes**. Phase 5
automated the same test and measured **not enforced within nine hundred
seconds**, with sixty-one successful calls logged in the window. The
simulator reflected the change immediately; the enforcement path did not.

**It is not a per-role score, because it does not vary by role.** It is a
property of the account, and it multiplies everything above. The practical
consequence is that *every number in the ranking is a floor, not a ceiling*: the
scores describe access as configured, and the account has demonstrated that
configured and effective are not the same thing for as long as half an hour
after a change.

**Which changes what an incident response can assume.** Revoking a compromised
credential is the first move in every playbook, and this environment says the
revocation will not necessarily take. The contingency is not a better policy;
it is a second control that does not depend on the first — deleting the
principal, or the resource, rather than narrowing what it may reach.

---

## Producing your own ranking

**The method is the deliverable; these numbers are one account at one moment.**
If you are working through this project against your own copy of CloudGuard,
your table will differ from this one — and where it differs most is where your
decisions differed from this run's. That is the point of scoring rather than
listing: the arithmetic is reproducible, and the inputs are yours.

Nothing above was computed by a tool. Every score comes from four things you can
read directly, and the commands to read them are below.

**COMMAND — every role in the account:**
```bash
aws iam list-roles --query 'Roles[].RoleName' --output text
```

↳ Entries beginning `aws-service-role/` or `AWSServiceRole` are AWS's own
service-linked roles, created by the services that use them. They are not yours
to score, and the account's copy of Project 2's standard says so.

**COMMAND — then, for each role that is yours:**
```bash
aws iam list-attached-role-policies --role-name <role>
aws iam list-role-policies --role-name <role>
aws iam get-role --role-name <role> \
  --query 'Role.[AssumeRolePolicyDocument,RoleLastUsed]'
```

↳ The first two give blast radius and escalation: what it can do, and whether
any of that can reach further. The third gives persistence and reachability, and
`RoleLastUsed` — which is worth reading even though it scores nothing, because a
role nobody has ever assumed is exposure with no return, and that is a judgement
the numbers cannot make for you.

**Two places your numbers are most likely to diverge from this table:**

- **The standing role.** This run removed it, because Project 2 permitted either
  removal or narrowing. A run that narrowed it instead would have a role here to
  score, and it would rank near the top — same blast radius as the JIT role,
  with the persistence column reading 5 instead of 2.
- **The CI identity's policy.** `manage-cloudguard` lists the services this
  environment runs. An environment managing different things has a different
  list, and the score moves with it.

**And one column that will not change.** The revocability dimension below is a
property of the platform, not of your account's configuration. If your chaos
test behaves as this one did, it belongs in your ranking too — and if it does
not, that difference is more interesting than anything in the table.

## What this ranking is for

Two priorities fall out of it, and neither is the one a flat inventory would
have produced.

**First, the long-lived human credentials.** Four administrative users, two
without MFA, all with standing access keys. They outscore every role, they are
the least governed — no trust policy reaches them, which is why Project 2's
standard could not — and Project 2's closing report already named them as
outside the boundary of what was checked.

**And the concentration in CI.** `iam:*` and `cloudtrail:*` on one federated
identity that runs on every push. It ranks third — behind a role that cannot be
changed from here and a set of users that can — and it is the highest-scoring
thing in this account that is entirely under this project's control. Not wrong,
and worth knowing.

And one thing that falls out of the ranking in the other direction: the JIT
role scoring sixth is the ranking agreeing with Projects 1 and 2. The work that
reduced this account's risk is visible in these numbers, and so is where the
risk moved to.
