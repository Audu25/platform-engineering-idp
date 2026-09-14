# 0008. Terraform owns that a secret exists, never its value

- **Status:** Accepted
- **Date:** 2026-09-13
- **Phase:** 6

## Context

Terraform can create a Secrets Manager secret and its value together. The value then
lives in Terraform state, and a later apply compares the stored value with the live
one — rolling back any rotation made outside Terraform.

## Decision

Terraform creates the secret, its IAM access and its Pod Identity binding, and no
`aws_secretsmanager_secret_version`. Values are set and rotated out of band. The chart
mounts the secret as an optional read-only volume, so a service starts before a value
exists and picks the value up when it appears.

## Consequences

- No secret value is ever in Terraform state or a plan.
- A rotation cannot be silently undone by an apply.
- Values are the one piece of state not reproducible from the repository. A rebuilt
  environment has empty secrets until someone puts the values back, and the teardown
  runbook says so.
- In dev the recovery window is zero days so a torn-down environment can be rebuilt at
  once; with a longer window, a rebuild inside it fails on the reserved name.
