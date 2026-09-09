output "repository_urls" {
  description = "Repository URLs keyed by service name, for CI pushes and Helm values."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Repository ARNs keyed by service name, for scoped pull policies."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "registry_id" {
  description = "Registry account ID used by docker login."
  value       = one(values(aws_ecr_repository.this)).registry_id
}
