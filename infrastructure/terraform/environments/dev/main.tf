module "network" {
  source             = "../../modules/network"
  name               = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "eks" {
  source              = "../../modules/eks"
  name                = var.cluster_name
  subnet_ids          = module.network.private_subnet_ids
  cluster_version     = var.cluster_version
  admin_role_arn      = var.admin_role_arn
  public_access_cidrs = var.public_access_cidrs
  instance_types      = var.instance_types
  capacity_type       = var.capacity_type
  desired_size        = var.desired_size
  min_size            = var.min_size
  max_size            = var.max_size
  # Private nodes need outbound connectivity before bootstrap can complete.
  depends_on = [module.network]
}

# The registry is deliberately independent of the cluster: images outlive any
# single cluster, and Phase 3 publishes to it before Argo CD consumes it.
module "ecr" {
  source           = "../../modules/ecr"
  repository_names = local.service_names
  namespace        = var.cluster_name
}
