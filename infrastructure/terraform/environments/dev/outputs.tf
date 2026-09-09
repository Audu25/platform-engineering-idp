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

output "ecr_repository_urls" {
  description = "Image repository URLs keyed by service, used by CI pushes and Helm values."
  value       = module.ecr.repository_urls
}

output "addon_versions" {
  description = "Resolved managed add-on versions running on the cluster."
  value       = module.eks.addon_versions
}

output "kubeconfig_command" {
  description = "Command that grants kubectl access using the configured administrator role."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
