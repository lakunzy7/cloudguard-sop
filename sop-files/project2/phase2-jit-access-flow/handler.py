"""CloudGuard JIT access broker.

Chain A, Project 2. Deliverable 2: the "request" half of a just-in-time
access flow that replaces the standing developer role.

What it does, in order:

  1. Requires a justification. A request without one is refused rather
     than logged as an anonymous use, because the point of a request
     flow is that the reason for the access is recorded alongside it.
  2. Assumes the JIT role for at most 900 seconds. The role's own
     MaxSessionDuration is also 900, so the ceiling is enforced twice -
     once here and once by IAM, where nothing running this code can
     reach around it.
  3. Writes the resulting credential to SSM Parameter Store as a
     SecureString, in the exact form of an AWS credentials file, so the
     requester can fetch it into a file and use it with one command.
  4. Returns a summary with no credential in it. The caller sees the
     session name, the role and the expiry; the credential itself
     travels by the other path. That keeps the response safe to read,
     log or screenshot.

What it deliberately does NOT do is decide who may ask. That check is
the Lambda's resource policy - see terraform/jit.tf - which IAM
evaluates before this code runs at all. Asking the function to police
its own callers would put the control somewhere a malformed request
could reach; the resource policy cannot be reached at all by a caller
who is not on it.

Author: Owofola Olakunle
"""

import logging
import os
from datetime import datetime, timezone

import boto3

# The request record. Every request - granted or refused - is written
# here with its justification, which is the half of "recorded access"
# that a credential alone cannot provide. CloudTrail will show that
# someone invoked this function; only this line shows what they said
# they needed it for.
logger = logging.getLogger()
logger.setLevel(logging.INFO)

JIT_ROLE_ARN = os.environ["JIT_ROLE_ARN"]
SSM_PARAMETER_NAME = os.environ["SSM_PARAMETER_NAME"]

# 900 seconds is the AssumeRole minimum, and the JIT role's
# MaxSessionDuration. Accepting the parameter at all - rather than
# hardcoding 900 - keeps the validation visible, so the bound is
# something a reader can see being enforced rather than something they
# have to assume.
MIN_DURATION = 900
MAX_DURATION = 900


def handler(event, context):
    justification = str(event.get("justification", "")).strip()
    if not justification:
        logger.warning("jit request REFUSED: no justification given")
        return {
            "granted": False,
            "reason": "a justification is required",
        }

    try:
        duration = int(event.get("duration_seconds", MAX_DURATION))
    except (TypeError, ValueError):
        logger.warning(
            "jit request REFUSED: duration not a number (justification=%r)",
            justification,
        )
        return {
            "granted": False,
            "reason": "duration_seconds must be a whole number of seconds",
        }

    if not MIN_DURATION <= duration <= MAX_DURATION:
        logger.warning(
            "jit request REFUSED: duration %s out of range (justification=%r)",
            duration,
            justification,
        )
        return {
            "granted": False,
            "reason": (
                f"duration_seconds must be between {MIN_DURATION} "
                f"and {MAX_DURATION}"
            ),
        }

    requested_at = datetime.now(timezone.utc)
    session_name = "jit-" + requested_at.strftime("%Y%m%d-%H%M%S")

    credentials = boto3.client("sts").assume_role(
        RoleArn=JIT_ROLE_ARN,
        RoleSessionName=session_name,
        DurationSeconds=duration,
    )["Credentials"]

    # Written in credentials-file form so the requester's next step is a
    # redirect rather than a parsing exercise. The [default] heading
    # means it can be dropped into its own file and used without a
    # --profile argument.
    profile = (
        "[default]\n"
        f"aws_access_key_id = {credentials['AccessKeyId']}\n"
        f"aws_secret_access_key = {credentials['SecretAccessKey']}\n"
        f"aws_session_token = {credentials['SessionToken']}\n"
    )

    boto3.client("ssm").put_parameter(
        Name=SSM_PARAMETER_NAME,
        Value=profile,
        Type="SecureString",
        Overwrite=True,
    )

    logger.info(
        "jit request GRANTED: session=%s duration=%ss expires=%s justification=%r",
        session_name,
        duration,
        credentials["Expiration"].isoformat(),
        justification,
    )

    return {
        "granted": True,
        "role": JIT_ROLE_ARN,
        "session_name": session_name,
        "duration_seconds": duration,
        "expires": credentials["Expiration"].isoformat(),
        "justification": justification,
        "credential_parameter": SSM_PARAMETER_NAME,
    }
