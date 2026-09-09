# EKS installs unversioned bootstrap networking and DNS. Promoting them to managed
# add-ons puts the version in state, so upgrades become reviewable plan changes
# instead of silent drift.
data "aws_eks_addon_version" "this" {
  for_each = toset([
    "vpc-cni",
    "kube-proxy",
    "eks-pod-identity-agent",
    "coredns",
    "aws-ebs-csi-driver",
  ])

  addon_name         = each.value
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

locals {
  # Resolved at plan time and shown in the diff, rather than hardcoded to versions
  # that may not exist in a given region or Kubernetes release.
  addon_versions = { for name, addon in data.aws_eks_addon_version.this : name => addon.version }
}

# Networking must exist before nodes can join, so these are created against the
# control plane and do not wait for the node group.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = local.addon_versions["vpc-cni"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = local.addon_versions["kube-proxy"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

# Pod Identity is the current AWS mechanism for giving a service account an IAM
# role. It is preferred over IRSA here because it needs no OIDC provider, no
# certificate thumbprint and no trust policy rewrite when the cluster is replaced.
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = local.addon_versions["eks-pod-identity-agent"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

# CoreDNS pods are scheduled workloads, so the node group must be able to run them
# before the add-on can report healthy.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = local.addon_versions["coredns"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.this]
}

# Without a CSI driver, PersistentVolumeClaims stay Pending. Phases 5 and 6 depend
# on this for Prometheus and Grafana storage.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = local.addon_versions["aws-ebs-csi-driver"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.this,
    aws_eks_addon.pod_identity,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  description        = "Volume lifecycle permissions for the EBS CSI controller."
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Binds the controller's service account to the role. The node role keeps no
# volume permissions, so a compromised workload cannot manage cluster storage.
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}
