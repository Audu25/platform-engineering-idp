variable "name" {
  description = "Resource name prefix."
  type        = string
}
variable "vpc_cidr" {
  description = "IPv4 /16 VPC range."
  type        = string
}
variable "availability_zones" {
  description = "Two availability zones for public and private subnets."
  type        = list(string)
}
