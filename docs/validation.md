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
| `helm lint --strict platform/helm/service` | Passed on Helm 3.19.0 after the digest change |
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

## Phase 4

Verified locally on 2026-09-09. This records configuration, rendering and
consistency checks only. **The Backstage portal has never been started, no
service has been scaffolded, and nothing has been applied to AWS.**

| Check | Result |
| --- | --- |
| `helm lint --strict platform/helm/service` | Passed after renaming the chart from `sample-service` and moving names onto the release |
| `helm lint --strict ... --values values-dev.yaml` | Passed |
| Render the shared chart | Deployment and Service both named `sample-service`, selectors matching, `app.kubernetes.io/part-of` stamped for catalog correlation |
| Render with `image.digest` set | Digest still reaches the container image reference after the chart rename |
| `check-platform.py` on the repository | Passed: 8 catalog entities, 2 groups, 1 registered service, 2 Argo CD applications |
| `check-platform.py` negative: owner not a Group | Caught `Component:sample-service` owned by a non-existent group |
| `check-platform.py` negative: skeleton file not named `.njk` | Caught `src/app.js` as shipping unrendered placeholders |
| `check-platform.py` negative: registered service with no Application | Caught an orphaned `gitops/environments/dev/orphan.yaml` |
| `check-platform.py` negative: broken YAML in a `.njk` skeleton file | Caught as invalid YAML once rendered |
| `check-platform.py` negative: broken YAML in the onboarding change | Caught as invalid YAML once rendered |
| First run of `check-platform.py` against the real catalog | Found a genuine modelling error: a `delivery-path` Component that no cluster object backs. Removed rather than special-cased |
| Registry derivation, `terraform console` (bootstrap) | `gitops/environments/dev` resolved to `["sample-service"]`; `publish_subjects` contained only the platform repository |
| Registry derivation, simulated onboarding | Adding `payments-api.yaml` produced `repo:OWNER/payments-api:ref:refs/heads/main` in the trust subjects and removing it reverted them |
| `platform_owned_services` exclusion | `sample-service` produced no trust subject, so no repository of that name could claim its credentials |
| `terraform fmt -check -recursive` | Passed with the new `services.tf` in both roots |
| `terraform validate` (dev, bootstrap) | Both passed on Terraform 1.14.5 |
| YAML parse of every non-template manifest | 22 files parsed, 0 failures |
| Backstage package versions | `@backstage/create-app` 0.9.1 and `@backstage/cli` 0.36.5 resolved through the npm registry, not from memory |

### Phase 4: not verified

A catalog that is internally consistent is not a catalog Backstage has accepted.
These remain unproven until the [Phase 4 runbook](phase-4-plan.md) is executed:

- That Backstage parses `app-config.yaml`, that the plugins named in it exist under
  those package names, and that the catalog locations resolve.
- That the template appears in the portal, that its `OwnerPicker` and
  `EntityPicker` resolve against the catalog, and that its parameter validation
  behaves as intended.
- That `fetch:template` with `templateFileExtension` renders exactly the `.njk`
  files and copies the GitHub Actions workflow untouched. This is the assumption
  the whole skeleton rests on and it has not been executed once.
- That `publish:github` can create a repository with those branch protection
  settings, and that `publish:github:pull-request` opens the onboarding pull
  request against the platform repository.
- That the scaffolded pipeline runs green in a fresh repository, including
  `npm ci` against the generated lockfile.
- That the cross-repository promotion works, and that the skip path prints
  correctly when `PLATFORM_REPO_TOKEN` is absent.
- That Terraform actually creates a repository and a trust subject for a newly
  onboarded service, which requires an apply.

The acceptance criterion for this phase — a developer creates a service through
the portal and receives a working repository and deployment — is therefore **not
yet met**. Every part exists and validates; none has been run end to end.

Note that the Phase 1 and Phase 2 rows above reference `platform/helm/sample-service`.
That path was correct when those checks ran; the chart moved to
`platform/helm/service` in Phase 4. The rows are left as recorded rather than
rewritten.

## Phase 5

Verified locally on 2026-09-09. This records configuration and rendering checks
only. **No cluster has run any of this, and no telemetry has ever been
collected.**

| Check | Result |
| --- | --- |
| `helm template` kube-prometheus-stack 90.0.0 with the platform values | Rendered 105 objects; values accepted by the chart |
| `helm template` loki 7.3.0 with the platform values | Rendered 9 objects in single-binary mode |
| `helm template` tempo 1.24.4 with the platform values | Rendered 5 objects |
| `helm template` opentelemetry-operator 0.122.0 with the platform values | Rendered 18 objects after a fix, below |
| Operator values schema | First attempt **failed**: `additional properties 'kubeRBACProxy' not allowed`. That key does not exist in chart 0.122.0 and was removed |
| Prometheus remote-write receiver | Present in the rendered `Prometheus` resource, which is what Tempo's metrics generator and the collector both write to |
| Prometheus service name | Rendered as `kps-prometheus`, matching the remote-write URLs in the Tempo values and the collector config |
| Grafana admin credential | Rendered as `secretKeyRef` to `grafana-admin`; no password appears in any file |
| EKS control-plane scrape jobs | No ServiceMonitor rendered for etcd, scheduler, controller-manager or kube-proxy |
| ServiceMonitor selectors | `serviceMonitorSelector: {}`, so monitors created by the operator are honoured rather than silently ignored |
| Chart rename to `service` at 0.4.0 | `helm lint --strict` passed; Deployment and Service still render as `sample-service` |
| Instrumentation annotation rendering | `instrumentation.opentelemetry.io/inject-nodejs: "observability/nodejs"` plus `OTEL_SERVICE_NAME=sample-service` |
| Opting out (`observability.instrumentation=""`) | Neither the annotation nor any `OTEL_` variable is rendered |
| `check-platform.py` on the repository | Passed: 8 catalog entities, 1 registered service, 7 Argo CD applications across 2 projects |
| `check-platform.py` negative: undefined Argo CD project | Caught `observability-tempo` naming a project that does not exist |
| `check-platform.py` negative: unpinned chart version | Caught `tempo` pinned to `>=1.0.0` rather than an exact version |
| `check-platform.py` negative: alert without `runbook_url` | Caught `ServiceDeploymentUnavailable` missing the annotation |
| `check-platform.py` negative: broken dashboard JSON | Caught `service-overview.json` as invalid JSON |
| Tempo span metric names | `traces_spanmetrics_calls_total` and `traces_spanmetrics_latency` read from Tempo v2.9.0 source, not from memory |
| Chart versions | kube-prometheus-stack 90.0.0, loki 7.3.0, tempo 1.24.4, opentelemetry-operator 0.122.0, all resolved from their repositories |
| YAML parse of every observability manifest | All parsed; dashboard ConfigMap JSON decodes to 10 panels and 2 template variables |

### Phase 5: not verified

A manifest that renders has never met an admission controller, a scheduler, or a
node with finite memory. These remain unproven until the
[Phase 5 runbook](phase-5-plan.md) is executed:

- That the whole stack fits and stays scheduled on the development node group.
  The requests were added up on paper, not observed under spot reclaim.
- That the operator's webhook injects the Node.js SDK into a pod whose container
  has `readOnlyRootFilesystem: true` and `automountServiceAccountToken: false`.
  Nothing here proves those settings and the injected init container coexist.
- That a request actually produces a span, that the span reaches Tempo, and that
  the trace-to-logs link resolves.
- That the collector's `k8sattributes` processor has sufficient RBAC in practice,
  and that pod association by connection works behind the cluster's networking.
- That Loki accepts OTLP at `/otlp` with these limits, and that the filelog
  receiver's container parser matches what containerd writes on these nodes.
- That `observability.metrics.enableMetrics` produces monitors Prometheus scrapes,
  which is the only thing feeding the telemetry-pipeline alerts.
- That the span-metric alert expressions match the label names Tempo emits, and
  that the dashboard's `service` variable populates.
- That an alert fires, appears in Alertmanager, and clears.

The acceptance criteria for this phase — a sample request produces a trace,
metrics and logs are discoverable, an alert is demonstrated — are therefore **not
yet met**. Every component is configured and validates; none has run.

## Phase 6

Verified locally on 2026-09-13. Configuration, rendering and admission policy
tests only. **Nothing has been applied to AWS, and no policy has admitted or
refused a request from a real API server.** The policy tests are the strongest
evidence in this phase, and the section below is explicit about what they do and
do not prove.

| Check | Result |
| --- | --- |
| `terraform fmt -check -recursive` and `validate` (dev, bootstrap) | Passed with the per-service roles, secrets, Pod Identity associations and developer access entry |
| `helm lint --strict` on the shared chart, default and dev values | Passed at chart 0.5.0 |
| Default render | ServiceAccount, Service, Deployment; no secret wiring |
| Dev render | Adds a SecretStore naming `arn:aws:iam::<account>:role/idp-dev-svc-sample-service` and an ExternalSecret reading `idp-dev/sample-service/config` into `sample-service-config` |
| Rendered Deployment | `serviceAccountName: sample-service`, token automount off, `fsGroup: 1000`, secret volume optional and mounted read-only at `/var/run/secrets/app` |
| Unquoted `aws.accountId` | Render refused with the quoting message, rather than producing an ARN in scientific notation |
| `secrets.enabled` without `aws` settings | Render refused |
| `serviceAccount.create=false` | Neither the ServiceAccount nor `serviceAccountName` rendered |
| `helm template` kyverno 3.9.1 with platform values | Rendered; one admission replica, cleanup controller absent, exceptions honoured only from `kyverno`, platform namespaces excluded from the webhook |
| `helm template` external-secrets 2.10.0 with platform values | Rendered; `ClusterSecretStore`, `ClusterExternalSecret`, `PushSecret`, `ClusterPushSecret` and `ClusterGenerator` CRDs absent and their reconcilers disabled; service account `external-secrets` |
| Kyverno CLI 1.19.1 | Downloaded and verified against the release `checksums.txt`; the Linux checksum pinned in CI came from the same file |
| `test-policies.sh` | **67 tests passed**: the rendered chart passes all six policies, including a pod shaped like the OpenTelemetry Operator's injection; 16 violations fail the policy each targets (first recorded as 17; corrected in Phase 7 by counting the fixture documents); platform components in `observability` are skipped by every policy |
| Scope check | All 33 pass and fail expectations were evaluated rather than excluded |
| `check-platform.py` | Passed: 10 Argo CD applications across 2 projects, 6 admission policies |

### Facts checked against sources rather than memory

| Claim | Source |
| --- | --- |
| `ClusterPolicy` v1 is served but deprecated; `ValidatingPolicy` v1 is served and not deprecated | CRDs rendered from the Kyverno 3.9.1 chart |
| `SecretStore` v1 has an AWS `role` field for per-store role assumption | CRD rendered from the external-secrets 2.10.0 chart |
| Argo CD 3.5.2 runs Helm `pre-delete` hooks, so Kyverno's webhook cleanup job runs on deletion | Argo CD v3.5.2 `docs/user-guide/helm.md` |
| Pod Identity trust can require `aws:RequestTag/kubernetes-namespace` and `kubernetes-service-account` | AWS EKS user guide, Pod Identity role trust |
| Pod Identity session tags are transitive, so a role chain needs `sts:TagSession` | AWS EKS user guide, Pod Identity session tags |
| `AmazonEKSViewPolicy` grants pods, events and `pods/log`, and does not include Secrets | AWS EKS user guide, access policy permissions |
| Kyverno labels its webhooks `webhook.kyverno.io/managed-by=kyverno`, which the teardown command selects on | Kyverno v1.19.1 `api/kyverno/constants.go` and its webhook controller |

### Gaps in the test suite, found and closed while building it

Three separate ways a green policy run could have proven nothing. Each was found
by a negative control, not by inspection.

1. **The CLI needs the custom resource definitions** to resolve SecretStore and
   ExternalSecret, and aborts the whole run without them. The upstream CRDs are
   407 KiB of schema; the vendored copies keep only the kind-to-resource mapping,
   under 1 KiB each.
2. **The CLI ignores namespace selectors unless labels come from a `variables`
   file.** Namespace objects under `clusterResources` are not read for this. Until
   that file existed, every policy was evaluating every namespace, and a control
   that moved a violation into another namespace went uncaught.
3. **The CLI grades an excluded resource as passing, whatever result was
   declared.** Declaring `fail`, `skip` and `pass` for the same excluded resource
   all produced a passing suite, so a policy scoped to nothing would pass every
   test. `test-policies.sh` now fails whenever an expected pass or fail was
   excluded, and `check-platform.py` requires a variables file and a skip result
   for every policy.

### Negative controls

Each control changes one thing in a scratch copy and must make the run fail.

| Control | Outcome |
| --- | --- |
| Image rule weakened to accept any image | Caught: the tagged pod, the foreign-registry pod and the tagged Deployment were admitted, "want fail, got pass" |
| Chart stops creating a service account | Caught: the rendered Deployment and both derived pods failed `idp-service-identity`, "want pass, got fail" |
| Secret prefix check without the trailing hyphen | Caught: `name-prefix-collision`, a service named `pay` mounting `payments-config`, was admitted |
| Policy's `namespaceSelector` removed | Caught: the observability component was evaluated and rejected, "want skip, got fail" |
| Policy selector typo, `idp-devv` | Caught by the scope check: five expectations never evaluated. **The CLI itself reported 67 passed** |
| Violation moved into `observability` | Caught by the scope check. **The CLI itself reported 67 passed**, both before and after the variables file was added |
| Validator: a policy without a `fail` result | Caught |
| Validator: a policy without a `skip` result | Caught |
| Validator: a test with no variables file | Caught |
| Validator: a policy with no namespace selector | Caught |
| Validator: a Deployment placed in the policies directory Argo CD applies | Caught |
| Validator: `aws.resourcePrefix` not matching Terraform's `cluster_name` | Caught |
| Validator: External Secrets service account not matching the Pod Identity association | Caught |

### Phase 6: not verified

- That EKS Pod Identity injects credentials into a pod whose service account and
  pod spec both disable token automounting. The Pod Identity webhook uses its own
  projected token, which should be independent, but nothing here has observed it.
- That the External Secrets controller's chained role assumption succeeds with
  transitive session tags, and that the trust-policy tag conditions admit the
  intended identities and refuse others.
- That an optional secret volume is populated once External Secrets creates the
  Secret after the pod started, and how long a rotation takes to reach the file.
- That the OpenTelemetry Operator's real injected init container matches the
  shape of the fixture, which was written from its known behaviour rather than
  captured from a running cluster.
- That Kyverno's admission webhook actually excludes the platform namespaces, and
  what `idp-dev` admission does while the single admission replica restarts.
- That sync waves install the CRDs before the resources that need them, and that
  Argo CD's pre-delete hook removes Kyverno's webhooks during teardown.
- That the developer access entry produces the `kubectl auth can-i` answers the
  runbook predicts.
- The Secrets Manager cost estimate, which is arithmetic on list prices.

The acceptance criteria for this phase — secret rotation reaches a workload,
invalid manifests are rejected, workloads have scoped AWS access — are therefore
**not yet met in a cluster**. Rejection of invalid manifests is demonstrated
against the policy engine offline; the other two have never run.

## Phase 7

Verified locally on 2026-09-13. Configuration, unit tests and drills only. **Nothing
has been applied to AWS, no promotion workflow has run, and no environment has been
synced by Argo CD.**

| Check | Result |
| --- | --- |
| `helm lint --strict` with default, dev, staging and production values | All four passed at chart 0.6.0 |
| Dev render | Two fixed replicas; no autoscaler or disruption budget |
| Staging render | No `replicas` field; autoscaler 2–3; disruption budget `maxUnavailable: 1` |
| Production render | No `replicas` field; autoscaler 3–6; disruption budget `maxUnavailable: 1` |
| Zone spread | Rendered in every environment alongside node spread |
| Per-environment identity | SecretStore role `idp-<env>-svc-sample-service` and key `idp-<env>/sample-service/config` in each environment |
| Autoscaler `minReplicas: 1` | Render refused |
| Autoscaler `maxReplicas` below `minReplicas` | Render refused |
| Disruption budget on one replica | Render refused |
| Tempo render with platform values | Overrides enable `span-metrics` and `service-graphs`; span metrics carry the `k8s.namespace.name` dimension |
| Instrumentation CRD from operator chart 0.122.0 | `spec.initContainerSecurityContext` exists in the served storage version |
| `terraform fmt` and `validate` (dev, bootstrap) | Passed with workload identity generalised to three environments |
| `check-platform.py` | Passed: 13 Argo CD applications, 6 admission policies, 3 environments |
| `test-policies.sh` | **188 tests passed** across the chart rendered for all three environments, 19 violations and out-of-scope components; all 36 pass and fail expectations evaluated |
| `test-alerts.sh` | promtool found 12 rules; all six test groups passed |
| `rollback-drill.sh` | Every check passed: shortcuts refused, two releases through every environment, idempotent re-promotion, production reverted without touching staging or dev, and the revert itself reverted |

### Promotion history rule, in a Git fixture

| Scenario | Outcome |
| --- | --- |
| dev, staging and production promoted in separate commits | Passed; two promotions traced |
| production edited by hand to a digest staging never ran | Refused |
| staging and production moved in the same commit | Production refused; staging, which dev had run first, passed |
| Shallow clone | Refused, rather than silently passing |

### Defects found in earlier phases

- **Tempo was never generating span metrics.** Phase 5 enabled the metrics generator
  but not its processors, which Tempo requires in its overrides. Every latency and
  error alert, the service dashboard and the new SLOs would have been permanently and
  silently inert. Found by reading the chart's values while adding the namespace
  dimension.
- **The injected init container was misdescribed in Phase 6.** Operator v0.158.0
  copies the first application container's security context onto it rather than
  leaving it empty. It is now set explicitly, and pod-security policy checks init
  containers.
- **The Phase 6 records said seventeen violations; there were sixteen.** Found by
  counting fixture documents instead of repeating the number. Corrected in the Phase 6
  runbook, the README and the Phase 6 record below.
- **One of this phase's own tests was wrong, not the rule it tested.** The first SLO
  test expected no alert five minutes in, but a rate is computed over the samples that
  exist, so the one-hour ratio already read 10%. The test now checks the rule's
  two-minute `for:` window instead.

### Negative controls

| Control | Outcome |
| --- | --- |
| SecretStore role check that ignores the environment | Caught: a production store using the dev role was admitted |
| ExternalSecret key prefix hardcoded to dev | Caught: staging and production's own ExternalSecrets were refused, and a production read of dev's key was admitted |
| Pod security that skips init containers | Caught: `privileged-init-container` was admitted |
| A policy that does not govern `idp-production` | Caught by the validator |
| A production service with no staging deployment | Caught by the validator |
| A production Application deploying to `idp-staging` | Caught by the validator |
| Production `aws.resourcePrefix` not matching Terraform | Caught by the validator |
| A recording rule with no expression | Caught by the validator |
| Burn-rate page without its traffic floor | Caught: the low-traffic test paged |

### Phase 7: not verified

- That span metrics arrive in Prometheus labelled `k8s_namespace_name` from real traffic.
  Every SLO alert selects on that label; if it is named differently or absent, they
  never match, and nothing reports that they cannot.
- That an autoscaler scales, since metrics-server has never run; and that disruption
  budgets hold during a real node drain or spot rebalance.
- That the `Promote` workflow runs, waits for a production Environment reviewer, and
  opens its pull request.
- That Argo CD syncs the staging and production Applications and their autoscalers
  without fighting over replicas.
- That the restricted Pod Security Standard admits an instrumented pod with the explicit
  init container security context.
- Every recovery path except reverting a promotion: removing Kyverno's webhooks, moving
  a secret's current version, rebuilding the cluster, and restoring Terraform state.

The acceptance criteria — a release passes staging, reaches production, and is recovered
using a tested runbook — are **not yet met in a cluster**. The recovery step is tested; the
release path it recovers has never run.

## Phase 8

Verified locally on 2026-09-14.

### End-to-end test on a real Kubernetes API server

`platform/scripts/e2e-kind.sh` passed on a fresh kind cluster in 253 seconds, using
kind v0.33.0 with the digest-pinned `kindest/node:v1.34.11` image. Kubernetes 1.34 was
used because this machine's Docker Desktop runs cgroup v1 on a WSL2 5.15 kernel, where
kubelets from Kubernetes 1.35 onward do not start; the default v1.37 image timed out
creating the control plane. CI runs the default image on cgroup v2 runners.

| Check | Result |
| --- | --- |
| Namespaces with the restricted Pod Security Standard | Applied as the platform defines them |
| Sample service from the shared chart, dev values | Admitted by Pod Security and available: non-root, read-only root filesystem, all capabilities dropped; answers `/readyz` |
| Mounted secret | Read by uid 1000 through `fsGroup` |
| Secret rotation | Reached the mounted file in 69 seconds with no container restart |
| Release whose image cannot be pulled | Both replicas stayed available and the service kept answering; `rollout undo` restored the release |
| Production values | HorizontalPodAutoscaler 3/6 and PodDisruptionBudget `maxUnavailable: 1` accepted; service answers `/readyz` |
| Kyverno 3.9.1 with the platform's values and policies | Enforcing |
| Rendered chart, server-side dry run, all three environments | Admitted |
| 19 violation fixtures, server-side dry run | All refused: 16 by Kyverno, 3 by Pod Security before Kyverno was reached |
| Platform components in `observability` | Admitted: policy leaves platform namespaces alone |

### Defects the end-to-end test found

The first runs failed four times before passing. One defect was in the platform, three
were in the test harness, and none would have been found without a real API server.

1. **Platform: an invalid CRD fixture.** The trimmed ExternalSecret CRD kept its
   `selectableFields` while its schema was replaced with an open one. The Kyverno CLI
   accepted it; the API server rejected it because the field selectors pointed at paths
   the schema no longer declared. `selectableFields` are now removed with the schema.
2. **Harness: Git Bash path conversion.** Git Bash rewrote the in-container path
   `/var/run/secrets/app/greeting` into a Windows path before it reached `kubectl`. The
   script now exempts `/var/run/` from conversion.
3. **Harness: admission ordering.** Two fixtures that borrow another service's identity
   named service accounts that did not exist, so the API server's ServiceAccount
   admission refused them before any webhook ran and Kyverno was never tested. The
   harness reported this as "failed for an unrelated reason" rather than passing it.
   The accounts are now created, and Kyverno refuses both.
4. **Harness: Secret volume sync on a reused cluster.** The first read of the mounted
   secret happened before the kubelet had synced a reset Secret. It is now polled, as the
   rotation check already was.

### Final regression, all phases

| Check | Result |
| --- | --- |
| `terraform fmt -check` and `validate` (dev, bootstrap) | Passed |
| `helm lint --strict` with default, dev, staging and production values | Passed |
| All four workflows (`ci`, `e2e`, `promote`, `terraform`) | Parse as YAML |
| All six scripts in `platform/scripts` | Pass `bash -n` |
| Python embedded in `e2e-kind.sh`, `test-policies.sh`, `test-alerts.sh` | Parses |
| `test-policies.sh` | 188 tests passed; all 36 pass and fail expectations evaluated, including after the CRD fixture fix |
| `test-alerts.sh` | 12 rules; every promtool test passed |
| `rollback-drill.sh` | Passed |
| `check-platform.py` | Passed, including every documentation link resolving |
| metrics-server 3.14.0 with platform values | Rendered two replicas, a disruption budget and host spread |

### Facts checked against sources

| Claim | Source |
| --- | --- |
| Tempo span-metric dimensions are looked up in resource attributes before span attributes, so the collector's `k8s.namespace.name` resource attribute becomes the `k8s_namespace_name` label the SLO alerts select on | Tempo v2.9.0 `spanmetrics.go` and `processor/util/util.go` |
| Kubernetes 1.34.11 node image digest | kind v0.33.0 release notes |
| helm/kind-action v1.15.0 | Commit resolved through the GitHub API |
| kind v0.33.0 | Windows binary verified against its published checksum |

### Negative control

| Control | Outcome |
| --- | --- |
| A runbook link changed to a file that does not exist | Caught by the documentation link check |

### Base image, chosen from scan data

The first CI run on `main` failed the Grype gate: the Debian 12 base carried high and
critical findings that Debian marks "won't fix" or has not fixed, so a strict gate
against it could never pass. Four candidates were scanned with Grype 0.118.0 on
2026-09-16, counting high and critical findings and how many had a fix available.

| Base image | Findings | High or critical | Of those, fixable |
| --- | --- | --- | --- |
| `node:24-bookworm-slim` (Debian 12) | 240 | 66 | 6 |
| `node:24-trixie-slim` (Debian 13) | 195 | 76 | 24 |
| `node:24-alpine` | 32 | 22 | 22 |
| `gcr.io/distroless/nodejs24-debian12` | 73 | 31 | 23 |

Alpine was chosen because every high or critical finding in it is fixable, which keeps
the gate strict rather than narrowing it to ignore what cannot be fixed. Its findings
were two OpenSSL packages, cleared by `apk upgrade`, and four in npm's own dependency
tree, cleared by removing npm from the image: a service with no dependencies does not
need a package manager in production. The skeleton the service template ships was
changed the same way, so scaffolded services inherit it.

The rebuilt image has not been scanned locally, because the Docker engine was stopped
again by the time the change was made. CI's scan is the check.

### Phase 8: not verified

- **Kubernetes 1.35 to 1.37 locally.** The platform targets 1.35 on EKS; the local run
  used 1.34 for the cgroup reason above. CI's default image covers 1.37.
- **Anything beyond the Kubernetes boundary.** The test creates the Secret directly and
  deploys with Helm, so External Secrets, EKS Pod Identity, ECR and Argo CD are still
  untested, as is the OpenTelemetry Operator's injection.
- **The cloud track of the demonstration**, which has never been performed.
- **The cost figures**, which are arithmetic on list prices rather than a bill.

The acceptance criteria are met for documentation, decision records, and a local
demonstration that now includes a real API server running the service, rotating its
secret, surviving a failed release and enforcing admission policy. They are **not met**
for a demonstration against the platform on AWS.
