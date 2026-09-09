# Short-lived OIDC credentials replace long-lived access keys in CI. There are no
# AWS secrets stored in GitHub, so there is nothing to leak or rotate.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates the provider's certificate chain against its own trust store for
  # this endpoint; the thumbprint is retained only to satisfy the API contract.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  repo              = "${var.github_owner}/${var.github_repo}"
  state_bucket_arn  = aws_s3_bucket.state.arn
}

# The subject claim is the only thing standing between this role and any other
# repository on GitHub, so it is matched explicitly rather than with a wildcard repo.
data "aws_iam_policy_document" "plan_assume" {
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
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

# Apply is restricted further: only a run executing in the protected GitHub
# Environment can assume it, which is where the human approval gate lives.
data "aws_iam_policy_document" "apply_assume" {
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
      values   = ["repo:${local.repo}:environment:${var.apply_environment}"]
    }
  }
}

# Both roles need to read, write and lock the state object. S3 native locking
# writes a .tflock object beside the state, so read-only access cannot plan.
data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [local.state_bucket_arn]
  }
  statement {
    sid    = "ReadWriteStateObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.state_bucket_arn}/idp/*"]
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.managed_role_prefix}terraform-plan"
  description          = "Read-only Terraform plan role assumed by GitHub Actions via OIDC."
  assume_role_policy   = data.aws_iam_policy_document.plan_assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role" "apply" {
  name                 = "${var.managed_role_prefix}terraform-apply"
  description          = "Terraform apply role assumed only from the protected GitHub Environment."
  assume_role_policy   = data.aws_iam_policy_document.apply_assume.json
  max_session_duration = 3600
}

# PowerUserAccess covers VPC, EKS, EC2, ECR and S3 while excluding IAM, so the
# blast radius stops short of the account's own permission model.
resource "aws_iam_role_policy_attachment" "apply_power_user" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "terraform-state-access"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.state_access.json
}

# EKS and its add-ons must create service-linked and workload roles, which
# PowerUserAccess denies. Grant that back only for this platform's name prefix,
# so the role cannot edit administrator or unrelated application roles.
data "aws_iam_policy_document" "apply_iam" {
  statement {
    sid    = "ManagePlatformRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.managed_role_prefix}*",
    ]
  }
  statement {
    sid    = "ManageServiceLinkedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
      "iam:GetRole",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "spot.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "platform-iam-management"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}
