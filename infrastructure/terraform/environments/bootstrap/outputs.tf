output "state_bucket" {
  description = "State bucket name for backend.hcl and the TF_STATE_BUCKET secret."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_region" {
  description = "Region the state bucket was created in."
  value       = var.aws_region
}

output "plan_role_arn" {
  description = "Role ARN for the pull request plan job; store as the AWS_PLAN_ROLE_ARN secret."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role ARN for the gated apply job; store as the AWS_APPLY_ROLE_ARN secret."
  value       = aws_iam_role.apply.arn
}

output "backend_hcl" {
  description = "Ready-to-write backend configuration for environments/dev/backend.hcl."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "idp/dev/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}

output "image_publish_role_arn" {
  description = "Role ARN for the CI image publish job; store as the AWS_IMAGE_PUBLISH_ROLE_ARN secret."
  value       = aws_iam_role.image_publish.arn
}

output "image_publish_subjects" {
  description = "OIDC subjects trusted to publish images. Review this after onboarding a service."
  value       = local.publish_subjects
}
