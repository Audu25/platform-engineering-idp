output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}
output "cluster_endpoint" {
  description = "Kubernetes API URL."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes minor version currently running."
  value       = aws_eks_cluster.this.version
}

output "node_role_arn" {
  description = "Managed node group instance role, referenced when scoping registry pulls."
  value       = aws_iam_role.nodes.arn
}

output "addon_versions" {
  description = "Resolved managed add-on versions, recorded so upgrades are visible in the plan."
  value       = local.addon_versions
}
