# GitOps deployment state

Files here record **what is deployed**, separately from `platform/helm`, which
records **how it is deployed**. CI writes only into this directory, so a
promotion commit can never alter the chart, the probes or the security context
it is deploying under.

Argo CD watches this path and `platform/helm/service` as two sources of
one Application. The chart supplies structure and defaults; the file here
supplies the image digest layered on top.

This directory is also the platform's service registry. Terraform enumerates
the files here to decide which ECR repositories exist and which GitHub
repositories may publish images into them, so adding a file is what makes a
service deployable at all — and is an infrastructure change, reviewed as one.

A conventional GitOps setup puts this directory in its own repository so that
application code and deployment state have independent histories and access
control. It stays here because the project is deliberately a single reviewable
repository; the directory boundary, the promotion job's narrow write scope and
the `CODEOWNERS`-style review of `gitops/**` give most of the same separation
without a second repository to clone. Splitting it out is a directory move plus
a `repoURL` change in the Argo CD Application.

## Environments

`environments/dev`, `environments/staging` and `environments/production` each hold one
file per service deployed there. A file's existence registers the service in that
environment — Terraform creates its IAM role and secret — and its digest is what
runs. A service enters each environment only through the one before it, and CI
checks from Git history that every digest already ran in the previous environment.

Move a release forward with the `Promote` workflow, or locally:

```bash
platform/scripts/promote-environment.sh --service sample-service --from staging --to production
```

## Promoting by hand

```bash
platform/scripts/promote-image.sh \
  --file gitops/environments/dev/sample-service.yaml \
  --repository 111122223333.dkr.ecr.eu-west-2.amazonaws.com/idp-dev/sample-service \
  --tag "$(git rev-parse HEAD)" \
  --digest sha256:<64 hex characters>
```

## Rolling back

`git revert` the promotion commit. The previous digest returns, Argo CD syncs it
and the image is still in the registry because tags are immutable and retention
keeps the last 20 images.
