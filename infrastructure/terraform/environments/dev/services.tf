# The gitops directory is the platform's service registry: a service exists in an
# environment exactly when it has deployment state there. Deriving the registry
# from those files is what lets onboarding and promotion be reviewed pull
# requests rather than edits here that neither the scaffolder nor a promotion
# workflow could make.
#
# The trade-off is that merging a file into gitops/environments creates AWS
# resources. That is why the directory is reviewed like infrastructure.
locals {
  gitops_root = "${path.root}/../../../../gitops/environments"

  # Services per environment. An environment with no directory yet simply has
  # no services, so adding production to the list is safe before anything is
  # promoted there.
  environment_services = {
    for environment in var.workload_environments : environment => sort([
      for file in fileset("${local.gitops_root}/${environment}", "*.yaml") : trimsuffix(file, ".yaml")
    ])
  }

  # Images are built once and promoted by digest, so one repository per service
  # serves every environment.
  discovered_services = sort(distinct(flatten(values(local.environment_services))))

  # An explicit list wins for image repositories, so a plan can be pinned or
  # tested without the directory. Workload identity always follows the registry.
  service_names = length(var.service_names) > 0 ? var.service_names : local.discovered_services
}
