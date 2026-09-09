# Phase 1 verification

Verified locally on 2026-09-09. This records observed results, not a claim of a
deployed platform or a successful hosted GitHub Actions run.

| Check | Result |
| --- | --- |
| `npm ci --ignore-scripts` | Passed with the generated package lockfile |
| `npm run check` | Both application source files passed Node.js syntax checks |
| `npm test` | All 5 HTTP tests passed on local Node.js 22.18.0 |
| `npm audit --audit-level=high` | Passed, 0 dependency vulnerabilities; application has no dependencies |
| `helm lint --strict platform/helm/sample-service` | Passed on Helm 3.19.0 |
| Helm lint with `values-dev.yaml` | Passed; registry placeholders still need replacement |
| `helm template sample ... --namespace idp-dev` | Rendered Deployment and Service with matching selectors, probes, resource bounds and security settings |
| `terraform fmt -check -recursive infrastructure/terraform` | Passed |
| `terraform init -backend=false -input=false` | Passed with signed HashiCorp AWS provider 6.63.0 |
| `terraform validate` | Passed on Terraform 1.14.5 |
| `docker build --pull -t sample-service:0.1.0 apps/sample-service` | Passed using Node.js 24.20.0 in the image |
| Hardened container smoke test | `/readyz` and `/healthz` returned 200 with read-only filesystem, dropped capabilities, no privilege escalation, 128Mi RAM and 0.5 CPU |
| Container identity | Verified UID 1000 |
| Container shutdown | SIGTERM logged and exit code 0 verified; temporary container removed |

The local image remains available as `sample-service:0.1.0`. No service container
was left running. Git was initialized on `main`; there is no remote or initial
commit yet. The source files are ready for review and committing.

The workflow contains an image package vulnerability gate using Anchore/Grype.
That scan has not run locally, so the built image is **not yet asserted to pass
the security gate**. Run the hosted workflow after pushing the repository to
validate the Linux CI environment and scan against its current database.

No Terraform plan/apply, AWS connectivity, live Kubernetes deployment, Kubernetes
API schema/admission validation, Argo CD installation/reconciliation, registry push,
or Backstage workflow was performed. Terraform validation checks configuration and
provider schemas, not AWS permissions, quotas, capacity or successful provisioning.
Helm lint/render checks do not prove a rollout will succeed on a real cluster.

Initial npm filesystem access, Terraform downloads and Docker access were restricted
by the execution sandbox. These operations succeeded when rerun with approved access.
