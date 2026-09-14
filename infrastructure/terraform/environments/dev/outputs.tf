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

output "environment_services" {
  description = "Services deployed to each environment, derived from gitops/environments."
  value       = local.environment_services
}

output "registered_services" {
  description = "Every service in any environment, each of which has one image repository."
  value       = local.service_names
}

output "external_secrets_role_arn" {
  description = "Role the External Secrets controller holds; it can only assume per-service roles."
  value       = aws_iam_role.external_secrets.arn
}

output "service_role_arns" {
  description = "Per-workload Pod Identity roles, keyed by environment/service."
  value       = { for name, role in aws_iam_role.service : name => role.arn }
}

output "service_secret_names" {
  description = "Secrets Manager secret each workload reads, keyed by environment/service. Values are set out of band."
  value       = { for name, secret in aws_secretsmanager_secret.service : name => secret.name }
}
