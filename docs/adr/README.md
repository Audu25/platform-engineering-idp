# Architecture decision records

Each record captures one decision that shaped the platform: the situation that
forced it, what was chosen, and what that choice costs. They are written so that
someone who disagrees can see exactly which assumption they disagree with.

A record is never edited to change its decision. When a decision is revisited, a new
record supersedes it and the old one's status says so.

| Record | Decision | Phase |
| --- | --- | --- |
| [0001](0001-deployment-state-in-this-repository.md) | Deployment state lives in this repository, not a separate GitOps repository | 3 |
| [0002](0002-deploy-by-digest-promote-by-copy.md) | Deploy by digest; promote by copying the digest | 3, 7 |
| [0003](0003-gitops-directory-is-the-service-registry.md) | The gitops directory is the service registry Terraform reads | 4 |
| [0004](0004-eks-pod-identity-over-irsa.md) | EKS Pod Identity over IAM Roles for Service Accounts | 2, 6 |
| [0005](0005-platform-injected-instrumentation.md) | The platform injects OpenTelemetry; services do not import an SDK | 5 |
| [0006](0006-kyverno-validatingpolicy-with-tests.md) | Admission policy as Kyverno ValidatingPolicy, tested in CI | 6 |
| [0007](0007-secrets-controller-without-secret-access.md) | The secrets controller holds no secret permission | 6 |
| [0008](0008-terraform-owns-secret-existence-not-values.md) | Terraform owns that a secret exists, never its value | 6 |
| [0009](0009-environments-as-namespaces.md) | Environments are namespaces in one cluster | 7 |
| [0010](0010-burn-rate-slo-alerts.md) | Reliability alerts are multi-window burn-rate SLO alerts | 7 |
