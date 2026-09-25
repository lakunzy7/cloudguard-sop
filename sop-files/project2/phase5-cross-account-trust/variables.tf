variable "aws_region" {
  description = "AWS region to deploy CloudGuard into. Pick a region with free-tier Lambda and S3 available."
  type        = string
  default     = "us-east-1"
}

variable "environment_name" {
  description = "Short name used as a prefix on every resource, keeps this environment identifiable and easy to tear down completely."
  type        = string
  default     = "cloudguard"
}

# ⚠️ CHANGE THIS: the operator identity in your own account. This is the
# allowlist for Project 2's JIT broker - the one principal permitted to
# request time-bound access. It defaults to the deploy user this run was
# made with.
variable "jit_requester_principal" {
  description = "The single principal allowed to request just-in-time access from the JIT broker."
  type        = string
  default     = "arn:aws:iam::113410693155:user/cloudguard@deploy"
}

# ⚠️ CHANGE THIS: a real second AWS account, standing in for the vendor in
# Project 2's cross-account scenario. It must be a genuine account - the
# trust policy names it, and a placeholder would make the finding
# hypothetical rather than constructed.
variable "vendor_account_id" {
  description = "The AWS account ID of the third-party integration trusted by Project 2's vendor role."
  type        = string
  default     = "637739132594"
}

variable "alert_email" {
  description = "Email address for the SNS topic that Chain C's automated response and compliance projects publish to. Leave blank to skip subscribing an email at apply time."
  type        = string
  default     = ""
}
