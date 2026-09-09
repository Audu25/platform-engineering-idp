variable "aws_region" {
  description = "Region holding the Terraform state bucket."
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_prefix" {
  description = "Prefix for the state bucket; the account ID is appended for global uniqueness."
  type        = string
  default     = "idp-tfstate"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,40}$", var.state_bucket_prefix))
    error_message = "Use lowercase letters, digits and hyphens; S3 bucket names are not case sensitive."
  }
}

variable "github_owner" {
  description = "GitHub account or organisation owning the platform repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name that may assume the Terraform roles."
  type        = string
}

variable "apply_environment" {
  description = "GitHub Environment gating apply; the apply role trusts only this environment."
  type        = string
  default     = "aws-dev"
}

variable "create_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. Set false if another stack already manages it."
  type        = bool
  default     = true
}

variable "managed_role_prefix" {
  description = "Prefix the apply role is allowed to manage IAM roles under. Must match the workload naming."
  type        = string
  default     = "idp-"
}

variable "owner" {
  description = "Cost allocation tag identifying the responsible person or team."
  type        = string
  default     = "platform-engineering"
}

variable "cost_centre" {
  description = "Cost allocation tag used to group platform spend in Cost Explorer."
  type        = string
  default     = "platform-idp"
}

variable "image_repository_prefix" {
  description = "ECR repository name prefix the publishing role may write to. Must match the dev environment's cluster_name prefix."
  type        = string
  default     = "idp-"
}
