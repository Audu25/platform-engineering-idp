variable "repository_names" {
  description = "Application image repositories to create, one per deployable service."
  type        = list(string)
  validation {
    condition     = length(var.repository_names) > 0
    error_message = "Create at least one repository."
  }
}

variable "namespace" {
  description = "Registry path prefix, keeping platform images separate from other account images."
  type        = string
  default     = "idp"
}

variable "untagged_expiry_days" {
  description = "Days before an untagged layer is deleted. Untagged layers are build residue."
  type        = number
  default     = 7
}

variable "tagged_image_count" {
  description = "Number of tagged images retained per repository for rollback."
  type        = number
  default     = 20
}
