# Verification

## Phase 1

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

## Phase 2

Verified locally on 2026-09-09. This records configuration checks only. **Nothing
in Phase 2 has been applied to AWS**, so no resource in this phase is asserted to
provision successfully.

| Check | Result |
| --- | --- |
| `terraform fmt -check -recursive infrastructure/terraform` | Passed across both roots and all three modules |
| `terraform init -backend=false` (bootstrap) | Passed; AWS provider 6.63.0 resolved, lockfile written |
| `terraform validate` (bootstrap) | Passed on Terraform 1.14.5 |
| `terraform init -backend=false -lockfile=readonly` (dev) | Passed with the committed lockfile unchanged by the ECR module |
| `terraform validate` (dev) | Passed with the ECR module, add-ons and spot node group |
| `helm lint --strict platform/helm/sample-service` | Still passes; the chart was not modified |
| YAML parse of both workflows | `ci.yaml` and `terraform.yaml` parse as valid YAML |
| Action pinning | `configure-aws-credentials` v6.2.4 and `github-script` v9 resolved to commit SHAs through the GitHub API, not copied from memory |

### Phase 2: not verified

Terraform validation checks configuration and provider schemas. It does not check
AWS permissions, quotas, regional capacity, or whether an apply succeeds. In
particular these remain unproven until the Phase 2 runbook is executed:

- The state bucket, its TLS-deny policy and S3 native locking behaviour.
- Whether the OIDC trust policies actually admit the intended workflow runs and
  reject others, and whether `PowerUserAccess` plus the scoped IAM grant is
  sufficient for a full EKS apply. An apply that fails on a missing permission is
  the expected way to discover a gap here.
- Managed add-on version resolution, which queries AWS at plan time and therefore
  cannot run without credentials.
- Spot capacity availability for `t3.medium`/`t3a.medium` in `eu-west-2`.
- EKS Pod Identity association for the EBS CSI controller.
- The plan and apply workflow jobs, which have never run.
- The teardown runbook, which the roadmap requires to be *tested*, not just written.

The acceptance criteria for this phase (private workers ready, operator access and
DNS working, remote state locking, teardown tested) are therefore **not yet met**.
The verification commands are in the [Phase 2 runbook](phase-2-plan.md).

## Phase 3

Verified locally on 2026-09-09. This records configuration and rendering checks
only. **No image has been published, no cluster has run Argo CD, and nothing in
Phase 2 or Phase 3 has been applied to AWS.**

| Check | Result |
| --- | --- |
| `helm lint --strict platform/helm/sample-service` | Passed on Helm 3.19.0 after the digest change |
| `helm lint --strict ... --values values-dev.yaml` | Passed with the environment overlay |
| Render with `image.digest` set | Produced `example.com/sample-service@sha256:0000...`; the digest reaches the container image reference |
| Render with no digest | Fell back to `sample-service:0.1.0`, so the tag path still works |
| Render with chart + `values-dev.yaml` + a promoted file | Produced the promoted `repository@digest`, which is the layering Argo CD performs |
| `promote-image.sh` with a valid digest | Wrote repository, tag and digest; output re-rendered correctly through Helm |
| `promote-image.sh` with `not-a-digest`, a short digest, missing arguments | Rejected all three with a non-zero exit and left the previous file contents intact |
| `kubectl kustomize platform/argocd/install` | Rendered 60 objects on kustomize v5.7.1 from the pinned Argo CD v3.5.2 manifests |
| Rendered installation, namespacing | Every namespaced object landed in `argocd`; no cluster-scoped object was given a namespace |
| Rendered installation, label transformer | `includeSelectors: false` left Deployment selectors untouched |
| YAML parse of workflows and manifests | `ci.yaml`, `terraform.yaml`, all Argo CD manifests and the GitOps state file parse as valid YAML |
| `terraform fmt -check -recursive infrastructure/terraform` | Passed with the new publishing role |
| `terraform validate` (bootstrap) | Passed on Terraform 1.14.5 with `ecr-publish.tf` |
| Argo CD version and manifest URL | `v3.5.2` confirmed as the latest release through the GitHub API, and the pinned `install.yaml` URL returned HTTP 200 |
| Action pinning | `amazon-ecr-login` v2.1.7 resolved to its commit SHA through the GitHub API, not copied from memory |

### Phase 3: not verified

Rendering is not admission, and a manifest that renders is not a rollout. These
remain unproven until the [Phase 3 runbook](phase-3-plan.md) is executed against a
real cluster and account:

- Whether the publishing role's trust policy admits a `main` run and rejects a
  pull request run, and whether its ECR actions are sufficient for a `docker push`.
- The push, digest capture and already-published reuse path, none of which can run
  without a registry.
- Whether the `promote` job can push a branch and open a pull request, which also
  depends on the repository setting that allows Actions to create pull requests.
- Argo CD installation, CRD registration, repository access, and whether the
  two-source `$values` reference resolves as documented.
- Automated sync, self-heal, prune, and the revert-to-roll-back behaviour.
- Whether the node role can pull from ECR over the NAT gateway.
- The updated teardown ordering, in particular Application finalizer behaviour.

The acceptance criteria for this phase (a merge builds and scans an image, an
approved Git change deploys it, reverting rolls it back) are therefore **not yet
met**. Every mechanism exists and validates; none has been observed end to end.
