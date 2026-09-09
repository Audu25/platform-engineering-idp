# One repository per service. Immutable tags mean a deployed digest can never be
# silently replaced, which is what makes Argo CD's recorded image trustworthy.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.namespace}/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Storage is billed per GB-month and CI produces an image per commit, so old
# images are expired rather than kept forever.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged layers"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Retain a bounded number of tagged images for rollback"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.tagged_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
