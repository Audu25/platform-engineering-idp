# 0004. EKS Pod Identity over IAM Roles for Service Accounts

- **Status:** Accepted
- **Date:** 2026-09-09
- **Phase:** 2, 6

## Context

Workloads need AWS credentials without long-lived keys. EKS offers two mechanisms.
IAM Roles for Service Accounts (IRSA) federates the cluster's OIDC issuer into IAM:
every role's trust policy names that issuer, and a replaced cluster has a new one.
EKS Pod Identity uses an agent add-on and an association API instead.

## Decision

Pod Identity, for both the EBS CSI controller and every service role. Each role's
trust policy requires the `kubernetes-namespace` and `kubernetes-service-account`
session tags that Pod Identity presents, so a role can only be obtained by the one
service account it was made for.

## Consequences

- No OIDC provider per cluster and no trust policy rewrite when a cluster is rebuilt;
  associations are recreated by Terraform with the cluster.
- A mistaken association to another service account fails closed rather than granting
  access, because the tag conditions do not match.
- Pod Identity session tags are transitive, so any role chain from a Pod Identity
  session must allow `sts:TagSession` — a detail that fails confusingly when missed.
- Pod Identity is EKS-specific. Moving to another Kubernetes distribution would mean
  moving back to OIDC federation.
