# The same registry the dev environment reads, for the opposite purpose: dev
# creates a repository per service, bootstrap grants that service's repository
# permission to push into it.
#
# Scaffolded repositories are named after the service, which is what makes this
# derivable. Services built inside the platform repository are excluded, because
# no separate repository of that name should be trusted just because a state file
# exists — otherwise creating a repository with the right name would be enough to
# obtain publish rights.
locals {
  gitops_dev_dir = "${path.root}/../../../../gitops/environments/dev"

  registered_services = sort([
    for file in fileset(local.gitops_dev_dir, "*.yaml") : trimsuffix(file, ".yaml")
  ])

  service_repos = [
    for service in local.registered_services : service
    if !contains(var.platform_owned_services, service)
  ]

  publish_subjects = concat(
    ["repo:${local.repo}:ref:refs/heads/main"],
    [for service in local.service_repos : "repo:${var.github_owner}/${service}:ref:refs/heads/main"],
  )
}
