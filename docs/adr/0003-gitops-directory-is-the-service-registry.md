# 0003. The gitops directory is the service registry

- **Status:** Accepted
- **Date:** 2026-09-09
- **Phase:** 4, extended in 6 and 7

## Context

Onboarding a service needs an image repository, publishing permission, and later an
IAM role and a secret per environment. The Backstage template can open a pull request
that adds files, but it cannot safely edit a Terraform list, and a promotion workflow
should not have to edit Terraform either.

## Decision

Terraform enumerates `gitops/environments/<environment>/*.yaml` with `fileset`. A file's
existence is what registers a service in an environment: it produces the ECR repository,
the publishing trust subject, the per-environment IAM role, the Secrets Manager secret
and the Pod Identity association.

## Consequences

- Onboarding and promotion are each one reviewed pull request that adds or changes a file.
- Merging a small YAML file creates AWS resources and grants permissions. That is an
  infrastructure change in a one-file disguise, so the directory is owned like
  infrastructure in `CODEOWNERS`.
- Terraform reads a directory outside its root, an unusual coupling that is documented
  in `services.tf`. An explicit `service_names` override still exists for testing.
