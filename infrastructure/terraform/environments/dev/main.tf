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
  # Private nodes need outbound connectivity before bootstrap can complete.
  depends_on = [module.network]
}
