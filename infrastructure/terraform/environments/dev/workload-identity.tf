# Scoped AWS access for workloads, through EKS Pod Identity.
#
# Every service in every environment gets its own IAM role and its own Secrets
# Manager prefix, and that role can read that prefix and nothing else. The node
# role carries no application permissions, so a pod that is not a registered
# workload — or a pod running under another workload's account — obtains nothing.
#
# Environments share one cluster and one set of IAM boundaries, separated by
# namespace and by name: idp-staging-svc-payments cannot read idp-production/*.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # One entry per service per environment it is deployed to, keyed
  # "environment/service". The namespace, role prefix and secret prefix all
  # derive from the same "<platform_prefix>-<environment>" string, and the
  # chart's aws.resourcePrefix in values-<environment>.yaml must equal it.
  workloads = {
    for pair in flatten([
      for environment, services in local.environment_services : [
        for service in services : { environment = environment, service = service }
      ]
      ]) : "${pair.environment}/${pair.service}" => {
      service   = pair.service
      namespace = "${var.platform_prefix}-${pair.environment}"
      prefix    = "${var.platform_prefix}-${pair.environment}"
    }
  }

  # Must match platform/security/values/external-secrets.yaml. The Pod Identity
  # association binds by name, so a mismatch fails closed: the controller runs
  # but can obtain no credentials.
  external_secrets_namespace       = "external-secrets"
  external_secrets_service_account = "external-secrets"
}

# --- Secrets -----------------------------------------------------------------

# Terraform owns that a secret exists and who may read it. It deliberately does
# not own the value. A secret version here would put the value in state, and a
# later apply could quietly roll a rotated secret back to whatever Terraform last
# wrote. The value is set out of band, once, and rotated the same way.
resource "aws_secretsmanager_secret" "service" {
  for_each = local.workloads

  name        = "${each.value.prefix}/${each.value.service}/config"
  description = "Runtime configuration for ${each.value.service}, synced into ${each.value.namespace} by External Secrets."

  # A deleted secret keeps its name reserved for the recovery window, so a
  # teardown and rebuild inside that window fails on "scheduled for deletion".
  recovery_window_in_days = var.secret_recovery_window_days
}

# --- External Secrets controller ---------------------------------------------

data "aws_iam_policy_document" "external_secrets_assume" {
  statement {
    sid     = "PodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    # Pod Identity presents the pod's namespace and service account as request
    # tags. Matching them means an association binding this role to any other
    # service account cannot obtain credentials, even if someone creates one.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = [local.external_secrets_namespace]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [local.external_secrets_service_account]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name                 = "${var.cluster_name}-external-secrets"
  description          = "External Secrets controller. Holds no secret access; can only assume per-workload roles."
  assume_role_policy   = data.aws_iam_policy_document.external_secrets_assume.json
  max_session_duration = 3600
}

# The controller has no Secrets Manager permission of its own. Each SecretStore
# names its workload's role, so every read happens with that workload's
# permissions and appears in CloudTrail under that role's name — not under one
# shared identity that can read everything.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid       = "ChainIntoWorkloadRoles"
    effect    = "Allow"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${var.platform_prefix}-*-svc-*"]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "chain-into-workload-roles"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.external_secrets_namespace
  service_account = local.external_secrets_service_account
  role_arn        = aws_iam_role.external_secrets.arn
}

# --- Per-workload roles ------------------------------------------------------

data "aws_iam_policy_document" "service_assume" {
  for_each = local.workloads

  statement {
    sid     = "PodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = [each.value.namespace]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [each.value.service]
    }
  }

  # Pod Identity session tags are transitive, so the controller's session carries
  # them into this AssumeRole. Without sts:TagSession here the chain is refused.
  statement {
    sid     = "ExternalSecretsChain"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.external_secrets.arn]
    }
  }
}

resource "aws_iam_role" "service" {
  for_each = local.workloads

  name                 = "${each.value.prefix}-svc-${each.value.service}"
  description          = "Scoped AWS access for ${each.value.service} in ${each.value.namespace}: its own secrets and nothing else."
  assume_role_policy   = data.aws_iam_policy_document.service_assume[each.key].json
  max_session_duration = 3600

  lifecycle {
    precondition {
      condition     = length("${each.value.prefix}-svc-${each.value.service}") <= 64
      error_message = "IAM role names are limited to 64 characters; shorten the platform prefix, environment or service name."
    }
  }
}

data "aws_iam_policy_document" "service" {
  for_each = local.workloads

  statement {
    sid     = "ReadOwnSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    # The slash after the service name matters: without it a service named "pay"
    # could read every secret belonging to "payments".
    resources = [
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${each.value.prefix}/${each.value.service}/*",
    ]
  }
}

resource "aws_iam_role_policy" "service" {
  for_each = local.workloads

  name   = "read-own-secrets"
  role   = aws_iam_role.service[each.key].id
  policy = data.aws_iam_policy_document.service[each.key].json
}

resource "aws_eks_pod_identity_association" "service" {
  for_each = local.workloads

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service
  role_arn        = aws_iam_role.service[each.key].arn
}
