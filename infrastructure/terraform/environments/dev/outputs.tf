output "cluster_name" {
  description = "EKS cluster name for aws eks update-kubeconfig."
  value       = module.eks.cluster_name
}
output "cluster_endpoint" {
  description = "EKS API endpoint; network reachability is required."
  value       = module.eks.cluster_endpoint
}
output "vpc_id" {
  description = "VPC identifier."
  value       = module.network.vpc_id
}
