output "vpc_id" {
  description = "Dedicated platform VPC ID."
  value       = aws_vpc.this.id
}
output "private_subnet_ids" {
  description = "Private subnets for EKS and worker nodes."
  value       = aws_subnet.private[*].id
}
