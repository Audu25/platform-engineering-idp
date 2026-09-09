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
