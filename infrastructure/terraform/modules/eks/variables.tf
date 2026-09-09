variable "name" {
  description = "Cluster name and IAM role prefix."
  type        = string
}
variable "subnet_ids" {
  description = "Private subnet IDs in at least two availability zones."
  type        = list(string)
}
variable "cluster_version" {
  description = "Explicit Kubernetes version."
  type        = string
}
variable "admin_role_arn" {
  description = "IAM role permitted to administer the cluster."
  type        = string
}
variable "public_access_cidrs" {
  description = "Trusted operator CIDRs, or empty for private API only."
  type        = list(string)
  default     = []
}
variable "instance_types" {
  description = "Managed node group x86_64 instance types."
  type        = list(string)
}

variable "capacity_type" {
  description = "Node purchasing model. SPOT is materially cheaper but nodes can be reclaimed at two minutes' notice."
  type        = string
  default     = "SPOT"
  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "desired_size" {
  description = "Starting node count. Two nodes let CoreDNS spread across availability zones."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Lower bound for the managed node group."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Upper bound. Spot reclaim is absorbed by replacing nodes, so leave headroom."
  type        = number
  default     = 4
}
