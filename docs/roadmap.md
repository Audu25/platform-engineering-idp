# Delivery roadmap

Each phase ends with a demonstrable capability. Phase 1 provides a foundation;
the complete self-service platform emerges when Phase 4 joins the delivery path.

| Phase | Scope | Completion evidence |
| --- | --- | --- |
| 1. Foundation | API, tests, Docker, Helm, Terraform modules, CI, Argo CD manifests | Tests pass, chart renders, Terraform validates, CI builds and scans the container |
| 2. AWS infrastructure | State bucket, plan/apply workflow, VPC/EKS, ECR, managed cluster add-ons, cost tags | Private workers ready; operator access and DNS work; remote state locks; teardown runbook tested |
| 3. GitOps delivery | Argo CD installation, GitOps repository, OIDC registry publishing, image digest promotion | Merge builds and scans an image; approved Git change deploys it; reverting the change rolls it back |
| 4. Developer self-service | Backstage catalog, template, ownership, repository scaffolding | Developer creates a service through the portal and receives a working repository and deployment |
| 5. Observability | Prometheus, Grafana, OpenTelemetry collector, trace backend, dashboards and alerts | A sample request produces a trace; service metrics and logs are discoverable; an alert is demonstrated |
| 6. Security and secrets | External Secrets with AWS Secrets Manager, Pod Identity, Kyverno, scoped RBAC | Secret rotation reaches a workload; invalid manifests are rejected; workloads have scoped AWS access |
| 7. Production workflows | Staging/production promotion, approvals, HPA, disruption budgets, SLOs, recovery | A release passes staging, reaches production, and can be recovered using a tested runbook |
| 8. Portfolio release | End-to-end test, architecture records, screenshots, demo, operational documentation | Reproducible create/deploy/observe/rollback demo and documented costs, limitations, and cleanup |

## Status

All eight phases are built. What differs is how far each has been proven. Nothing has
been applied to AWS, so the last column is empty on purpose; the detail behind every
cell is in [validation.md](validation.md).

| Phase | Verified offline | Verified on a Kubernetes API server | Run against AWS |
| --- | --- | --- | --- |
| 1. Foundation | Tests, chart lint, Terraform validate, hardened container smoke test | Service runs under restricted Pod Security, in kind | No |
| 2. AWS infrastructure | Terraform validate, provider schemas | — | No |
| 3. GitOps delivery | Promotion script checks, digest rendering, rollback drill | — | No |
| 4. Developer self-service | Catalog, template and service registry checks | — | No; Backstage never started |
| 5. Observability | Pinned charts render against platform values | — | No |
| 6. Security and secrets | 188 policy tests with negative controls | Admission refusals and secret rotation, in kind | No |
| 7. Production workflows | SLO alert unit tests, rollback drill, promotion history fixtures | Autoscaler and budget accepted; failed release rolled back, in kind | No |
| 8. Portfolio release | Documentation link check | End-to-end test passed in kind on Kubernetes 1.34 | No |

Kyverno is the planned policy engine because its Kubernetes-native YAML is easy
to include in service templates. Revisit this choice if policies require Rego or
non-Kubernetes enforcement. GHCR is an illustrative image URL in Phase 1; AWS ECR
is the intended AWS deployment registry in Phases 2–3.
