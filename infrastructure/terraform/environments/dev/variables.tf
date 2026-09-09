variable "aws_region" {
  description = "AWS region for the development environment."
  type        = string
  default     = "eu-west-2"
}
variable "cluster_name" {
  description = "Prefix for infrastructure resources."
  type        = string
  default     = "idp-dev"
}
variable "vpc_cidr" {
  description = "Dedicated VPC CIDR; subnet calculation reserves /24 blocks."
  type        = string
  default     = "10.42.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr))
    error_message = "Use an IPv4 /16 CIDR for this foundation."
  }
}
variable "availability_zones" {
  description = "Two distinct AZs in aws_region."
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Provide exactly two distinct availability zones."
  }
}
variable "cluster_version" {
  description = "Explicit EKS Kubernetes version; verify regional support before apply."
  type        = string
  default     = "1.35"
}
variable "admin_role_arn" {
  description = "Existing IAM role granted cluster administration via an EKS access entry."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.admin_role_arn))
    error_message = "Provide an existing AWS IAM role ARN, not an IAM user or STS session ARN."
  }
}
variable "public_access_cidrs" {
  description = "Trusted operator IPv4 CIDRs; an empty list keeps the API private only."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrnetmask(cidr)) && !endswith(cidr, "/0")])
    error_message = "Use valid restricted IPv4 CIDRs; /0 is not permitted."
  }
}
variable "instance_types" {
  description = "x86_64 instance types. Several comparable types widen the spot capacity pool and reduce reclaim."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "capacity_type" {
  description = "SPOT keeps the development cluster affordable; ON_DEMAND removes reclaim risk for demos."
  type        = string
  default     = "SPOT"
  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "desired_size" {
  description = "Starting worker count."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum worker count."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum worker count; headroom absorbs spot reclaim."
  type        = number
  default     = 4
  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be greater than or equal to min_size."
  }
}

variable "service_names" {
  description = "Override the services that receive an image repository. Empty derives them from gitops/environments/dev, which is the normal case."
  type        = list(string)
  default     = []
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
