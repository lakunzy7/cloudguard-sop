# Chain A — Closing Report

**Identity and Access.** Projects 1, 2 and 3 of the Expadox Cloud Security portfolio, run end to end against one AWS account, `113410693155`, inside the Expadox Organization.

This document does not summarise three exercises. It records what changed in a real account and what is left, so that Chain B's posture and runtime work can start from a measured identity layer rather than from an assumption about one.

---

## What Chain A set out to do

The brief for the chain is a single sentence: make CloudGuard's identity layer genuinely understood and tested, rather than individually patched role by role. That is a different target from "fix the risky permissions," and it is why the three projects are shaped the way they are.

Each of them could have been finished by tightening a policy and asserting the result. Each of them instead ends with the same move — **remove the thing, watch something specific fail, put it back, and prove the putting-back worked** — because a tightened policy that has never been tested is a claim, and this chain produced evidence instead.

---

## What each project changed

### Project 1 — the workload's access

The Lambda function ran under `AmazonS3FullAccess`. Phase 2 read the account's own CloudTrail data to find out what it actually did, and the trail could not answer: **data events are off by default on every trail**, so the account had no record of a single `GetObject` or `PutObject`. The selector had to be added before the question could be asked at all.

With that in place the policy was right-sized to two statements — `s3:GetObject` on the bucket, `s3:PutObject` on `metadata/*` — and proven by deliberately removing one and confirming a *specific* failure before restoring it.

Static credentials went next. A GitHub OIDC provider and a deploy role replaced them, with the trust pinned to one repository and branch by immutable ID. A scheduled drift check now compares the live policy against real usage every Monday.

### Project 2 — the human's access

`cloudguard-standing-developer-access` carried `PowerUserAccess` permanently, assumable by any principal in the account holding MFA, and **had never been assumed** — established in Phase 1 from two independent sources, each with a control proving the blank was a finding rather than a broken query.

It was removed and replaced by access that has to be asked for: a broker function assumes a role for **900 seconds** on request, only for a principal named in its resource policy, with every request carrying a justification that is logged. Phase 3 proved the expiry by *using* the credential after its window and letting AWS refuse it.

A cross-account trust was then constructed against `637739132594`, shown to admit a caller that should not have been admitted, and fixed with an `sts:ExternalId` condition — the same commands run before and after, so the comparison is one experiment rather than two descriptions.

`TRUST-POLICY-STANDARD.md` holds four checkable requirements, and Phase 7 applied them to every role in the account, **including the ones this project built**.

### Project 3 — the shape of the whole

The first two projects reviewed roles one at a time, which cannot see a path that only exists between two of them. Project 3 built the graph.

**The inventory** — from Principal Mapper, not from reading policies: 16 nodes, 6 of them administrative, 4 edges, 24 tracked policies.

**The escalation question** — `preset privesc *` returns **nothing**. No principal in this account can reach administrative access it was not already granted.

**The specific route** — `iam:PassRole` plus `lambda:CreateFunction`, tested live against the account's real roles rather than simulated, and **not found**. The explanation fits in one line of policy: `PowerUserAccess` means everything except IAM, and `iam:PassRole` is an IAM action.

**The chaos work** — `IAM-CHAOS-FRAMEWORK.md` documents a safe way to ask "if this permission is revoked right now, what breaks," and a real test followed it. The result was not the expected one: **the removal was not enforced.** A statement was deleted from the broker's policy and the broker kept issuing credentials — 31 minutes between the break and the restore, with 27 minutes of successful grants inside that gap. The automated version, written separately, independently reproduced it and put a harder number on it: **not enforced within 900 seconds**, with 61 successful calls logged in a window where the policy permitted none.

**The ranking** — `ENTITLEMENT-RISK-SCORING.md` scores every principal on four multiplied dimensions. It puts the four IAM users above every role, and names the CI identity as the highest-scoring thing in the account that this project controls.

**The seeded path** — a genuine new escalation route was introduced, caught by the graph and not by eye, fixed by narrowing rather than deleting, and proven by a clean rerun in which the node count held while the edge disappeared.

---

## The identity and access baseline Chain B inherits

This is the part meant to be used. Everything below is checkable against the account as it stands.

**The principals.** Four IAM users and seven roles. Five of the roles are this environment's — `cloudguard-github-actions-deploy`, `cloudguard-jit-broker-role`, `cloudguard-jit-developer-access`, `cloudguard-process-upload-role`, `cloudguard-vendor-integration`. Two are not, and are accounted for rather than unknown: `OrganizationAccountAccessRole` and `AWSReservedSSO_Billing_52b75615faffa5a4`.

**The reachability map.** Four edges, each derived rather than described:

| From | To | By |
|---|---|---|
| `cloudguard-jit-broker-role` | `cloudguard-jit-developer-access` | `sts:AssumeRole` |
| `cloudguard-jit-developer-access` | `cloudguard-jit-broker-role` | Lambda function edit |
| `cloudguard-jit-developer-access` | `cloudguard-process-upload-role` | Lambda function edit |
| `AWSServiceRoleForSSO` | `AWSReservedSSO_Billing_…` | trust-document update |

Two of those run between the same pair of roles in opposite directions. That loop is real, it is rated Low, and it is the class of reach that reading either policy on its own cannot show.

**The ranking.** Eight scored rows. The three that matter most to anything Chain B builds: the four IAM users at **500**, `OrganizationAccountAccessRole` at **375**, `cloudguard-github-actions-deploy` at **200**.

**A standard, with a known edge.** `TRUST-POLICY-STANDARD.md` states four requirements. One of them — the subject condition — was found to be the wrong instrument for Identity Center roles. **A trust policy does not always describe who can get in**, and three roles in this account are cases of that.

**And one measurement that multiplies everything.** A permission that is removed does not necessarily stop working. Every number in the ranking is therefore a **floor rather than a ceiling**, and any control Chain B assumes is enforcing from the moment it is applied is assuming something this chain measured and found false.

---

## What is still standing, and known

**The operator access key `AKIARUZ6N3ARQJIWU7NI` is active.** It is the credential every command across all three projects ran as. It is not covered by any deliverable in Chain A, and it remains one of the larger pieces of standing access in the account. Named here because a handoff that omits it would be describing a cleaner account than exists.

**Four IAM users hold administrative access, and two have no MFA device.** `ogaziechi` and `Samuel` have administrative permissions and no second factor; `cloudguard@deploy` and `lakunzy7` carry passkeys and standing access keys. No trust policy reaches an IAM user, which is precisely why Project 2's standard could not see them and why Project 3's ranking put them first.

**The concentration in CI.** `cloudguard-github-actions-deploy` carries `iam:*` and `cloudtrail:*` on everything. It can rewrite any permission in the account and it can stop the account recording what it does. Every decision behind it was correct — Terraform has to manage IAM, and its trust is pinned as tightly as it can be — and it is still a concentration, ranked third and entirely within this chain's control.

**The vendor role is unused.** `cloudguard-vendor-integration` is a real cross-account trust that nothing currently uses. It is kept because it is what Project 2's deliverables 5 through 7 were built against, and because removing the artifact of a completed demonstration would leave the standard's first rule with nothing to point at.

**The JIT role is the deliberate exception.** `cloudguard-jit-developer-access` holds `PowerUserAccess` and ranks sixth — the ranking agreeing with the two projects before it. The permission did not change from the standing role it replaced; everything around it did. It lasts fifteen minutes, requires a request, is recorded, and only one principal can obtain it.

---

## How this connects forward

Chain B's attack-path analysis is where this baseline pays off. It will produce exposure and misconfiguration findings of its own, and the value is in correlating the two lists rather than publishing them side by side.

Three specific things to correlate against:

**Rank first, then correlate.** `ENTITLEMENT-RISK-SCORING.md` already orders the identity side by real risk. An exposure finding reachable by a principal scoring 500 and one reachable only by a role scoring 12 are not the same finding, and the ranking is what makes that visible without re-deriving it.

**Treat reachability as a graph, not a list.** The four edges above are the account's actual identity paths, including the loop. An attack path that crosses two roles has to be computed from those edges; a per-principal review will not find it. Project 3's own Phase 7 demonstrated the converse — a role whose policy looked narrow was a route into an administrative principal, and only the graph showed it.

**Assume controls are slow, and measure.** The revocation lag is the single most transferable finding in this chain. Any Chain B mitigation that depends on a permission change taking effect immediately inherits it, and the honest response is a second control that does not depend on the first — not a better policy.

---

## The chain in one paragraph

Chain A found a workload holding full access to a data store and gave it two statements. It found standing human access that had never been used and replaced it with access that expires in fifteen minutes and has to be asked for. It found a cross-account trust that admitted the wrong caller and closed it with a condition. It then built the graph that showed those three fixes were individually correct but not, by themselves, sufficient — and it measured something none of the three briefs asked for: that in this account, revoking a permission does not necessarily revoke it. Nothing in this chain is asserted. Every one of those statements has a frame, a command or a console behind it, and the ones that came out the awkward way are the ones worth reading first.
