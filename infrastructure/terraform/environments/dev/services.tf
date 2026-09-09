# The gitops directory is the platform's service registry: a service exists in
# dev exactly when it has deployment state. Deriving the registry from those
# files is what lets the Backstage template onboard a service with one reviewed
# pull request instead of an edit here that the scaffolder cannot make.
#
# The trade-off is that merging a file into gitops/environments/dev creates AWS
# resources. That is why the directory is reviewed like infrastructure.
locals {
  gitops_dev_dir = "${path.root}/../../../../gitops/environments/dev"

  discovered_services = sort([
    for file in fileset(local.gitops_dev_dir, "*.yaml") : trimsuffix(file, ".yaml")
  ])

  # An explicit list wins, so a plan can be pinned or tested without the
  # directory. Empty means "whatever is registered", which is the normal case.
  service_names = length(var.service_names) > 0 ? var.service_names : local.discovered_services
}
