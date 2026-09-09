# Phase 3 publishing identity. Kept separate from the Terraform roles because
# building an image is a different privilege from changing infrastructure: this
# role can push layers and read repositories, and can do nothing else.

# Only a run on the default branch may publish. Pull requests build and scan the
# same image but never obtain these credentials, so a fork or an unmerged branch
# cannot place an artifact in the registry that Argo CD would later deploy.
data "aws_iam_policy_document" "image_publish_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repo}:ref:refs/heads/main"]
    }
  }
}

data "aws_iam_policy_document" "image_publish" {
  # The authorisation token endpoint is account-wide and cannot be scoped to a
  # repository, so it is granted alone rather than alongside the write actions.
  statement {
    sid       = "AuthenticateToRegistry"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Layer uploads plus the read actions Docker needs to skip layers already
  # present. No delete or lifecycle permission: retention belongs to Terraform.
  statement {
    sid    = "PushPlatformImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ecr:*:${data.aws_caller_identity.current.account_id}:repository/${var.image_repository_prefix}*",
    ]
  }
}

resource "aws_iam_role" "image_publish" {
  name                 = "${var.managed_role_prefix}ci-image-publish"
  description          = "Pushes application images to ECR from the default branch via OIDC."
  assume_role_policy   = data.aws_iam_policy_document.image_publish_assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "image_publish" {
  name   = "ecr-publish"
  role   = aws_iam_role.image_publish.id
  policy = data.aws_iam_policy_document.image_publish.json
}
