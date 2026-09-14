# 0009. Environments are namespaces in one cluster

- **Status:** Accepted
- **Date:** 2026-09-13
- **Phase:** 7

## Context

A release path needs staging and production. Separate EKS clusters give the strongest
isolation, but each adds a $73-a-month control plane, a NAT gateway and nodes — roughly
tripling the fixed cost of a platform built to be torn down and rebuilt between sessions.

## Decision

`idp-dev`, `idp-staging` and `idp-production` are namespaces in one cluster, each with its
own deployment state, chart values, IAM roles and secrets, the restricted Pod Security
Standard, and the same admission policies. Promotion moves a digest one environment at a
time, and CI proves from Git history that it ran in the previous environment first.

## Consequences

- One cluster's cost, with environment separation for identity, secrets, policy and
  deployment state.
- No separation from failures of the cluster itself: a control-plane issue, node-group
  exhaustion or a cluster-wide misconfiguration affects every environment at once.
- Staging shares node capacity with production, so a load test in staging can starve it.
- Nothing in the charts, policies or promotion flow assumes a single cluster. Moving
  production out is a Terraform root and an Argo CD destination change. This record
  should be superseded when the platform carries real production traffic.
