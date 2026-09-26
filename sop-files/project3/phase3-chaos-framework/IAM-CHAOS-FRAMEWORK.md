# CloudGuard IAM chaos framework

A safe, repeatable method for answering one question:

> **If this permission were revoked right now, what would break?**

Every test in this document follows the same seven steps. The method matters
more than any individual test, because the point is to be able to run the next
one without inventing a new approach — and to be able to hand it to someone
else, who runs it and gets the same answer.

This is the framework referred to by Chain A, Project 3's deliverable 4. It was
written *after* Projects 1 and 2 rather than before, because both of those
projects ran tests of this kind by hand and the method is what they had in
common. The worked examples at the end are those tests, described as instances
of the method rather than as one-offs.

---

## The five rules

**1. Name the claim.**
Not "is this policy right?" but a sentence that can be false: *only the broker
role can assume the JIT role.* A test of a vague claim produces a vague result.

**2. Name the control that enforces it.**
Which specific thing makes the claim true? A policy statement, a condition key,
a trust policy's principal, a session duration. If you cannot point at the exact
control, you are not ready to break anything — you do not yet know what you are
testing.

**3. Change exactly one thing.**
Two changes produce one result and no attribution. This is the rule that gets
broken most often, usually by making a "small improvement" while you are in
there.

**4. Predict the failure before you cause it.**
Write down the error you expect and the action it should name. A test with a
prediction can be wrong, which is how you learn something. A test without one is
just a change you observed.

**5. Have the restore ready before you break anything — and verify it.**
Not "I can put it back". The exact command, or the exact file, ready to go. Then
after restoring, run the test again and watch it pass. A repair that has not
been re-tested is a hope.

---

## The procedure

**Step 1 — Record the current state.**
Copy the artifact you are about to change: the policy JSON, the trust document,
the role's configuration. Verbatim, before anything moves. This is your restore
point and your evidence of the "before".

**Step 2 — Write the prediction.**
The claim, the control, and the specific failure you expect. Be exact about the
error text where you can: *the call will be refused with AccessDenied naming
s3:PutObject and stating that no identity-based policy allows it.*

**Step 3 — Break it.**
Change only the control named in rule 2, and nothing else.

**Step 4 — Try to use it.**
Run the test that should now fail. Not a proxy for it, and not a check of the
configuration — the actual thing the permission was for.

**Step 5 — Attribute the result.**
Compare what happened against the prediction. **If the failure does not match,
the test has failed, not the control.** A refusal you cannot attribute is a
refusal you cannot use.

**Step 6 — Restore.**
Put the state back exactly as recorded in step 1.

**Step 7 — Verify the restore.**
Run the test again. It should now succeed. This step is the one most often
skipped and the only one that proves the system is as you left it.

---

## Before you start: what makes a test unsafe

Any one of these is a reason not to run the test until it is resolved.

- **It touches data you cannot recreate.** Revoking a permission is safe; using
  that revocation to delete something is not.
- **The change cannot be reverted in the same session.** A policy edit is
  reversible in seconds. A deleted role is reversible only if you recorded its
  configuration first — which is step 1, and the reason step 1 exists.
- **The failure mode is not known in advance.** If you cannot say what breaks,
  you cannot say what to watch for.
- **It depends on a credential that expires.** Anything with a session lifetime
  puts a clock on your test. Know the clock before you start it. (See failure
  mode 2 below; this is not hypothetical.)
- **It changes something a third party depends on.** CloudGuard is a shared
  account with shared users. A test that breaks someone else's access is not a
  test, it is an outage.

---

## The four ways a test lies to you

These are the failure modes this portfolio has actually hit. Each one produced a
result that looked like an answer and was not.

### 1. The refusal came from a different control

Project 2 needed to prove that a standing role could no longer be assumed. The
obvious approach — tighten the policy, attempt the assumption, watch it fail —
would have proven nothing, because the role's trust policy *already* required
MFA and the operator had no MFA device. The attempt would have been refused
either way, and the walkthrough would have reported a pass it had not earned.

The fix is ordering: prove the call **succeeds** first, then change the control,
then prove it fails. Only then does the failure belong to the thing you changed.

**The general form:** a control that was already refusing cannot be said to have
started refusing. Establish the "before" by making the thing work.

### 2. The credential expired mid-test

Project 3 attempted a privilege-escalation route using a credential with a
fifteen-minute lifetime. Between minting it, writing a test function and
packaging it, the window closed — and the attempt returned `ExpiredToken`
instead of the `AccessDenied` the test was looking for.

The refusal was real and was not the one under test. The account had refused the
*caller*, not the *action*, and the captured evidence would have claimed the
escalation was blocked when nothing had been tested at all.

**The general form:** know the lifetime of every credential in the test, and run
the parts in the order that keeps the shortest one alive.

### 3. The restore that was not verified

Step 7 exists because step 6 is easy to get almost right. A restored policy that
differs by one statement, a role that came back with the wrong trust document —
both look repaired and are not.

**The general form:** restoring is a change, and changes get tested. Run the
test again and watch it pass before declaring the environment whole.

### 4. The change that had not taken effect yet

During Project 3's own chaos test, `sts:AssumeRole` was removed from the JIT
broker's policy so that the access flow would break. Terraform applied it and
reported success. The next invocation granted the request anyway — the broker
issued a credential — and for a moment that looked like evidence that the
control was not load-bearing at all.

It was not. **IAM policy changes are eventually consistent.** The removal was
correct and in place as far as the API was concerned; it had simply not reached
the enforcement path when the test ran. The grant was real, and it proved
nothing either way.

**The general form:** a successful apply is not a change in force. Some
resources take effect the moment the call returns; some do not, and the ones
that matter here are usually in the second group. Before observing, confirm the
change has landed by **attempting the thing it is meant to prevent** — not by
re-reading the resource. A read-back reports the API's view, which was always
correct, and says nothing about what a call will actually be allowed to do.

Where a delay is expected, measure it rather than guessing: retry the attempt at
a fixed interval and record how many seconds pass before it changes. That number
is worth writing down, because it sets the budget for every later test of the
same kind — the same way the delivery latency measured in Project 1's Phase 2
sets the budget for reading CloudTrail.

---

## Worked examples

Each of these is a real test run in this environment, described as an instance
of the seven steps.

### Project 1 — is the right-sized policy load-bearing?

**Claim.** The Lambda's S3 access is governed by the scoped policy and nothing
else.
**Control.** The `s3:PutObject` statement in that policy.
**Prediction.** With the statement removed, the function will still read its
input object and will then fail at the write, with an error naming
`s3:PutObject` and stating that no identity-based policy allows it.
**What happened.** Exactly that. The function logged `Processing s3://…` — the
read succeeded — and died at `handler.py` line 48 on the write, with the
predicted error.
**Attribution.** The error named the action, the resource, and the reason, so
there was no ambiguity about which control refused it.
**Restore and verify.** The statement went back; a further upload produced the
metadata object again.

The value of this test is that the scope was proven *load-bearing* rather than
merely sufficient. A function succeeding under a narrow policy shows only that
the policy is at least enough; removing a piece and watching the failure name
*that* permission shows it is doing the work.

### Project 2 — does a session actually expire?

**Claim.** A credential from the JIT flow dies at its stated expiry.
**Control.** The 900-second session duration requested from STS.
**Prediction.** The same file used after its window will be refused, by AWS, with
`ExpiredToken`.
**What happened.** Used inside the window at 18:09, refused at 18:24 against an
expiry of 18:22.
**Attribution.** Nothing else changed between the two runs — same file, same
command, same principal — which is what makes the clock the cause.
**Restore and verify.** Not applicable: the credential was meant to expire, and
its expiry *was* the confirmation.

### Project 3 — does the PassRole escalation route exist?

**Claim, from the graph.** The JIT role can reach the broker role through Lambda.
**Control.** `iam:PassRole` on the broker role.
**Prediction.** The creation attempt will be refused with an error naming
`iam:PassRole` and the broker role.
**What happened.** Refused — but only on the second attempt. The first returned
`ExpiredToken`, which is failure mode 2 above, and had to be discarded as
evidence and re-run with fresh credentials.
**Attribution.** The eventual error named the action, the resource and the
reason; the first one named none of those things, which is what marked it as
unusable rather than merely disappointing.
**Restore and verify.** Nothing was broken — the call was refused before
creating anything — and the function list confirmed it.

---

## Why this is worth doing at all

A permission that has never been removed is a permission nobody has tested.
Reading a policy tells you what it *should* allow; it cannot tell you what
depends on it, which is the question that matters when someone proposes
tightening it.

The tests above are small. Their value is not in their size but in the habit
they establish: **change one thing, predict what breaks, watch, attribute, put
it back, and prove the putting-back worked.** Run often enough, that habit
catches a dependency before an incident does — and it does so with a rollback
already in hand.

The method's real output is not the pass or fail of any single test. It is the
confidence to keep tightening permissions, because you will find out cheaply
when you have gone too far.
