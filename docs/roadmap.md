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

Kyverno is the planned policy engine because its Kubernetes-native YAML is easy
to include in service templates. Revisit this choice if policies require Rego or
non-Kubernetes enforcement. GHCR is an illustrative image URL in Phase 1; AWS ECR
is the intended AWS deployment registry in Phases 2–3.
