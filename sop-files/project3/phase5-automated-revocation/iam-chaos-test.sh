#!/usr/bin/env bash
#
# CloudGuard IAM chaos test.
#
# Chain A, Project 3, deliverable 6.
#
# Runs one safe-revocation test end to end: record the state, remove one
# control, try the thing that depends on it, check that the failure belongs
# to what was removed, put it back, and prove the putting-back worked.
#
# It automates the method in IAM-CHAOS-FRAMEWORK.md rather than replacing
# it. Every step is one a person would take by hand. What the automation
# adds is that the order is fixed, the restore cannot be forgotten, and the
# waiting is measured rather than guessed.
#
# ── The waiting, and why this script exists in this shape ──────────────
#
# Project 3's first attempt at this test failed for a reason worth
# remembering: the permission was removed, Terraform reported success, and
# the capability kept working for at least twenty-seven minutes. IAM's
# simulator reflected the change immediately; the enforcement path did not.
#
# So this script does not assume a removal takes effect. It removes the
# control, then retries the dependent call until it is refused, and reports
# how long that took. If it is never refused inside the timeout, that is
# the result — exit 2, INCONCLUSIVE — and not a pass. A script that treated
# "still working" as "nothing to report" would reproduce the exact mistake
# the manual test made.
#
# Author: Owofola Olakunle
#
# Usage: scripts/iam-chaos-test.sh [--dry-run] [--timeout SECONDS]
#
# Exits:
#   0  the control was load-bearing, the failure named it, and the restore held
#   2  INCONCLUSIVE — the removal was not enforced within the timeout
#   3  UNATTRIBUTED — something failed, but not the thing that was removed
#   4  RESTORE FAILED — the environment is not as it was found

set -euo pipefail

POLICY_ARN="${POLICY_ARN:-arn:aws:iam::113410693155:policy/cloudguard-jit-broker}"
STATEMENT_SID="${STATEMENT_SID:-AssumeTheJitRoleOnly}"
FUNCTION_NAME="${FUNCTION_NAME:-cloudguard-jit-broker}"
EXPECTED_ACTION="${EXPECTED_ACTION:-sts:AssumeRole}"
TIMEOUT="${TIMEOUT:-900}"
INTERVAL="${INTERVAL:-15}"

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

WORK="$(mktemp -d)"

# ── The restore is armed before anything is changed ───────────────────
#
# The framework's rule 5: have the restore ready before you break
# anything. An earlier version of this script restored only on the success
# path — so an interrupt during the retry loop, which is the longest part
# of the run and the likeliest moment to lose patience, would have left the
# policy exactly as the test wanted it: broken, and nobody watching.
#
# The trap fires on every exit, including a signal, and the restore is
# idempotent so running it twice is harmless.
ORIGINAL=""
BROKEN=""
restore_policy() {
  [ -n "$BROKEN" ] || return 0
  aws iam set-default-policy-version --policy-arn "$POLICY_ARN" \
    --version-id "$ORIGINAL" > /dev/null 2>&1 || true
  aws iam delete-policy-version --policy-arn "$POLICY_ARN" \
    --version-id "$BROKEN" > /dev/null 2>&1 || true
  BROKEN=""
}
trap 'restore_policy; rm -rf "$WORK"' EXIT INT TERM

step() { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

# ── Step 0: preflight ─────────────────────────────────────────────────
# Everything the test will touch is confirmed to exist before anything is
# changed. A test that discovers a missing resource halfway through has
# already made a change it now has to undo.

step "Preflight"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
note "account : $ACCOUNT"
note "policy  : $POLICY_ARN"
note "function: $FUNCTION_NAME"
note "removing: statement '$STATEMENT_SID'"
note "expecting: a refusal naming '$EXPECTED_ACTION'"

ORIGINAL="$(aws iam get-policy --policy-arn "$POLICY_ARN" \
  --query Policy.DefaultVersionId --output text)"
note "current default version: $ORIGINAL"

aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$ORIGINAL" \
  --query PolicyVersion.Document --output json > "$WORK/original.json"

if ! jq -e --arg sid "$STATEMENT_SID" \
    'any(.Statement[]; .Sid == $sid)' "$WORK/original.json" > /dev/null; then
  echo "FAIL: the policy has no statement with Sid '$STATEMENT_SID'" >&2
  exit 3
fi

# ── Step 1: the prediction ────────────────────────────────────────────
# Written down, and checked afterwards. The framework's rule 4: a test with
# a prediction can be wrong, which is how you learn something.

step "Prediction"
note "removing '$STATEMENT_SID' will stop the dependent call, and the"
note "failure will name '$EXPECTED_ACTION'."

if [ "$DRY_RUN" -eq 1 ]; then
  note "(dry run — stopping here; nothing has been changed)"
  echo "$ACCOUNT" > /dev/null
  exit 0
fi

# ── Step 2: remove exactly one control ────────────────────────────────

step "Removing the statement"

# A managed policy keeps at most five versions, so a sixth would fail. On a
# test meant to be run on demand, that failure would arrive on the fifth
# run and look like a bug in the environment.
COUNT="$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" \
  --query 'length(Versions)' --output text)"
if [ "$COUNT" -ge 5 ]; then
  OLDEST="$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" \
    --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate)[0].VersionId' \
    --output text)"
  note "version limit reached — deleting oldest non-default ($OLDEST)"
  aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$OLDEST"
fi

jq --arg sid "$STATEMENT_SID" \
  '.Statement |= map(select(.Sid != $sid))' "$WORK/original.json" > "$WORK/broken.json"

BROKEN="$(aws iam create-policy-version --policy-arn "$POLICY_ARN" \
  --policy-document "file://$WORK/broken.json" --set-as-default \
  --query 'PolicyVersion.VersionId' --output text)"
note "created version $BROKEN, now the default"

# ── Steps 3 and 4: try it, until it fails ─────────────────────────────
# The dependent call is retried until it is refused, because a removal is
# not a removal until something observes it.

step "Trying the dependent call"

ELAPSED=0
REFUSED=0
while [ "$ELAPSED" -le "$TIMEOUT" ]; do
  aws lambda invoke --function-name "$FUNCTION_NAME" \
    --payload '{"justification":"automated chaos test"}' \
    --cli-binary-format raw-in-base64-out "$WORK/out.json" > /dev/null 2>&1 || true

  if grep -q '"granted": true' "$WORK/out.json" 2>/dev/null; then
    note "t+${ELAPSED}s  still permitted"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    continue
  fi

  REFUSED=1
  note "t+${ELAPSED}s  refused"
  break
done

if [ "$REFUSED" -eq 0 ]; then
  step "INCONCLUSIVE"
  note "the removal was not enforced within ${TIMEOUT}s."
  note "restoring, so the environment is not left changed."
  restore_policy
  note "restored to version $ORIGINAL"
  echo
  echo "This is a finding, not a failure of the test: a permission can be"
  echo "removed from every policy that grants it and keep working. See"
  echo "IAM-CHAOS-FRAMEWORK.md, failure mode 4."
  exit 2
fi

# ── Step 5: attribute the failure ─────────────────────────────────────
# The framework's rule: if the failure does not name the thing that was
# removed, the test has failed, not the control.

step "Attributing the failure"

if grep -q "$EXPECTED_ACTION" "$WORK/out.json" 2>/dev/null; then
  note "the failure names '$EXPECTED_ACTION' — attribution is clean"
  ATTRIBUTED=1
else
  note "the failure does NOT name '$EXPECTED_ACTION':"
  note "$(head -c 400 "$WORK/out.json")"
  ATTRIBUTED=0
fi

# ── Step 6: restore ───────────────────────────────────────────────────

step "Restoring"
restore_policy
note "default version is $ORIGINAL again"

# ── Step 7: verify the restore ────────────────────────────────────────
# Step 6 is easy to get almost right. This is the step that proves it.

step "Verifying the restore"
VERIFIED=0
for _ in 1 2 3 4 5 6 7 8; do
  aws lambda invoke --function-name "$FUNCTION_NAME" \
    --payload '{"justification":"verify the restore"}' \
    --cli-binary-format raw-in-base64-out "$WORK/verify.json" > /dev/null 2>&1 || true
  if grep -q '"granted": true' "$WORK/verify.json" 2>/dev/null; then
    VERIFIED=1
    break
  fi
  sleep "$INTERVAL"
done

if [ "$VERIFIED" -eq 1 ]; then
  note "the dependent call works again"
else
  note "the dependent call did NOT recover — the environment is not as it was found"
  exit 4
fi

echo
if [ "$ATTRIBUTED" -eq 1 ]; then
  echo "PASS: '$STATEMENT_SID' is load-bearing, the refusal named it, and the restore held."
  exit 0
fi
echo "Test ran, but the refusal did not name '$EXPECTED_ACTION' — see above."
exit 3
