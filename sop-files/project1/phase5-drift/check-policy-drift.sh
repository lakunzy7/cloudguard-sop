#!/usr/bin/env bash
#
# CloudGuard policy drift check.
#
# Chain A, Project 1, deliverable 9.
#
# Re-runs the Phase 2 analysis — what does this role actually do with
# S3, according to CloudTrail — and compares it against what the role's
# policy currently allows. A right-sized policy today is not guaranteed
# to stay right-sized, because the function's code can change and the
# policy can be widened to match it.
#
# Author: Owofola Olakunle
#
# Exits 0 when the policy and the observed usage agree, 2 when they do
# not, and 3 when there was not enough traffic to decide. The distinction
# between "no drift" and "no data" is deliberate: a quiet week is not
# evidence of a well-scoped policy, and reporting it as a pass would be
# reporting health that was never verified.

set -euo pipefail

ROLE_NAME="${ROLE_NAME:-cloudguard-process-upload-role}"
# ⚠️ CHANGE THIS: your own account ID. See "What you must change"
# in this repository's README.
POLICY_ARN="${POLICY_ARN:-arn:aws:iam::113410693155:policy/cloudguard-process-upload-s3-scoped}"
# ⚠️ CHANGE THIS: your own account ID. See "What you must change"
# in this repository's README.
TRAIL_BUCKET="${TRAIL_BUCKET:-cloudguard-cloudtrail-113410693155}"
LOOKBACK_DAYS="${LOOKBACK_DAYS:-7}"
REGION="${AWS_REGION:-us-east-1}"

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "CloudGuard policy drift check"
echo "  account       : $ACCOUNT"
echo "  role          : $ROLE_NAME"
echo "  policy        : $POLICY_ARN"
echo "  lookback      : $LOOKBACK_DAYS days"
echo "  trail bucket  : $TRAIL_BUCKET"
echo

# ---------------------------------------------------------------------
# 1. What the policy allows right now.
# ---------------------------------------------------------------------
echo "Reading the current policy..."

VERSION="$(aws iam get-policy --policy-arn "$POLICY_ARN" \
  --query 'Policy.DefaultVersionId' --output text)"

aws iam get-policy-version --policy-arn "$POLICY_ARN" \
  --version-id "$VERSION" --query 'PolicyVersion.Document' --output json \
  | jq -r '[.Statement[].Action] | flatten | .[]' \
  | sort -u > "$WORKDIR/allowed.txt"

echo "  default version $VERSION allows $(wc -l < "$WORKDIR/allowed.txt") action(s)"
sed 's/^/    /' "$WORKDIR/allowed.txt"
echo

# ---------------------------------------------------------------------
# 2. What the role actually did, from CloudTrail data events.
#
#    Only data events matter here: every S3 object-level call the
#    function makes is one, and management events would bury it in
#    control-plane noise from the rest of the account.
# ---------------------------------------------------------------------
echo "Downloading CloudTrail logs for the last $LOOKBACK_DAYS days..."

PREFIX="$TRAIL_BUCKET/AWSLogs/$ACCOUNT/CloudTrail/$REGION"
FOUND=0

for i in $(seq 0 $((LOOKBACK_DAYS - 1))); do
  DAY="$(date -u -d "-${i} days" +%Y/%m/%d)"
  if aws s3 ls "s3://$PREFIX/$DAY/" > /dev/null 2>&1; then
    aws s3 cp "s3://$PREFIX/$DAY/" "$WORKDIR/" --recursive --quiet \
      --exclude "*" --include "*.json.gz" 2>/dev/null || true
    FOUND=$((FOUND + 1))
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "  no CloudTrail objects found in the window"
  echo
  echo "RESULT: INSUFFICIENT DATA — nothing to compare."
  exit 3
fi

gunzip -f "$WORKDIR"/*.gz 2>/dev/null || true
echo "  $FOUND day(s) of logs, $(ls "$WORKDIR"/*.json 2>/dev/null | wc -l) file(s)"
echo

# Map to the policy's own vocabulary. CloudTrail reports an S3 call as
# eventSource "s3.amazonaws.com" plus eventName "GetObject"; the policy
# writes it as "s3:GetObject". Normalising both to the policy's form is
# what lets the two sets be compared directly.
# NOTE the .Records[] — a CloudTrail log file is an object wrapping an
# array, not a stream of records. Without it every select() below runs
# against {"Records":[...]} itself, matches nothing, and the check
# reports "insufficient data" forever while looking like it works.
jq -r --arg role "$ROLE_NAME" '
  .Records[]
  | select(.eventCategory == "Data")
  | select(.userIdentity.arn // "" | test($role))
  | "\(.eventSource | sub("\\.amazonaws\\.com$"; "")):\(.eventName)"
' "$WORKDIR"/*.json 2>/dev/null | sort -u > "$WORKDIR/observed.txt" || true

if [ ! -s "$WORKDIR/observed.txt" ]; then
  echo "RESULT: INSUFFICIENT DATA — logs present, but this role made no"
  echo "recorded data calls in the window. That is not the same as a pass."
  exit 3
fi

echo "Observed usage:"
sed 's/^/    /' "$WORKDIR/observed.txt"
echo

# ---------------------------------------------------------------------
# 3. Compare, in both directions.
# ---------------------------------------------------------------------
comm -13 "$WORKDIR/allowed.txt" "$WORKDIR/observed.txt" > "$WORKDIR/usage_not_allowed.txt" || true
comm -23 "$WORKDIR/allowed.txt" "$WORKDIR/observed.txt" > "$WORKDIR/allowed_not_used.txt" || true

DRIFT=0

if [ -s "$WORKDIR/usage_not_allowed.txt" ]; then
  DRIFT=1
  echo "DRIFT — the role is doing things its policy does not allow."
  echo "These calls are being denied, which means the function is failing:"
  sed 's/^/    /' "$WORKDIR/usage_not_allowed.txt"
  echo
fi

if [ -s "$WORKDIR/allowed_not_used.txt" ]; then
  DRIFT=1
  echo "DRIFT — the policy allows more than the role has ever used."
  echo "This is the original finding returning, or arriving from a new direction:"
  sed 's/^/    /' "$WORKDIR/allowed_not_used.txt"
  echo
fi

if [ "$DRIFT" -eq 0 ]; then
  echo "RESULT: NO DRIFT — the policy and the recorded usage agree exactly."
  exit 0
fi

echo "RESULT: DRIFT DETECTED — review above."
echo
echo "If the change was intentional, re-derive the policy from a fresh"
echo "observation window rather than editing it to silence this check."
exit 2
