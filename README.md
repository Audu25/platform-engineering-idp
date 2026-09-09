# Platform Engineering IDP

A portfolio Internal Developer Platform that will let application developers
create and deploy services through Backstage without maintaining infrastructure, Kubernetes manifests or delivery pipelines themselves.

**Current scope: Phase 3 GitOps delivery.** The API and deployment definitions are
implemented, the AWS environment is applyable, and the delivery path is closed: a
merge publishes a scanned image to ECR by digest, a promotion pull request moves
that digest into deployment state, and Argo CD reconciles it into the cluster.
Backstage and the shared platform components will be built incrementally across
[eight phases](docs/roadmap.md).
This is a production-oriented development foundation, not a production deployment.

```mermaid
flowchart TD
  Developer --> Backstage[Backstage portal: Phase 4]
  Backstage --> Template[Service template: Phase 4]
  Template --> Repo[GitHub application repository]
  Repo --> CI[GitHub Actions: test, build, scan]
  CI --> Registry[Amazon ECR: publish by digest]
  Registry --> GitOps[Promotion pull request: gitops/]
  GitOps --> Argo[Argo CD: automated sync]
  Argo --> EKS[Kubernetes / EKS: Phase 2 provisioning]
  EKS --> Observability[Prometheus / Grafana / OpenTelemetry: Phase 5]
  EKS --> Security[Kyverno / External Secrets: Phase 6]
```

## Repository layout

```text
platform-engineering-idp/
├── apps/
│   └── sample-service/           # API, native tests, Dockerfile
├── infrastructure/
│   └── terraform/
│       ├── environments/
│       │   ├── bootstrap/       # State bucket, GitHub OIDC provider, Terraform roles
│       │   └── dev/             # Provider, inputs, module composition, backend
│       └── modules/
│           ├── network/         # VPC, subnets, routing and NAT
│           ├── eks/             # Cluster, IAM access, logs, add-ons, managed workers
│           └── ecr/             # Per-service image repositories and retention
├── platform/
│   ├── helm/sample-service/     # Deployment and ClusterIP Service
│   ├── argocd/
│   │   ├── install/            # Pinned Argo CD installation
│   │   ├── applications/       # App-of-apps root and per-service Applications
│   │   └── project.yaml        # Scoped AppProject
│   ├── scripts/                # Image promotion
│   └── kubernetes/              # Bootstrap namespace
├── gitops/
│   └── environments/dev/       # Deployed image digests; written by promotion
├── .github/
│   ├── workflows/ci.yaml       # Tests, checks, build/scan, publish, promote
│   ├── workflows/terraform.yaml # Plan on pull requests, gated apply on main
│   └── dependabot.yml
├── docs/                       # Plans, roadmap, teardown runbook and evidence
└── README.md
```

Application source, cloud resources, platform configuration and deployment state
have separate ownership boundaries. A monorepo keeps the project inspectable in one
clone; [`gitops/README.md`](gitops/README.md) explains why deployment state is a
directory here rather than a second repository, and what splitting it would cost.
Phase 4 templates will create per-service repositories. GitHub requires workflows in
the root `.github/workflows` directory.

## Run and test the API

Use Node.js 24 LTS for parity with CI and the container. The source also supports
Node.js 22. Run these commands from the repository root:

```powershell
cd apps/sample-service
npm ci --ignore-scripts
npm run check
npm test
npm start
```

In another terminal:

```powershell
curl.exe http://localhost:8080/
curl.exe http://localhost:8080/healthz
curl.exe http://localhost:8080/readyz
```

| Endpoint | Purpose |
| --- | --- |
| `GET /` | Service identity, version and greeting |
| `GET /healthz` | Process liveness, returns 200 |
| `GET /readyz` | Traffic readiness, returns 200; becomes 503 when draining |

HEAD is supported, unknown routes return 404, and other methods return 405.
`PORT` defaults to 8080; `APP_VERSION` defaults to 0.1.0. The service is stateless,
has no database, authentication or public ingress, and writes JSON logs to stdout.
It excludes query strings, bodies and headers from logs. Avoid secrets in URL paths.

**Why native Node.js:** no runtime packages are needed for three small routes.
The built-in test runner exercises real HTTP responses without introducing a
framework. The lockfile establishes the dependency workflow for future packages.
App construction is separate from process startup so tests can use ephemeral ports.
SIGTERM marks the service unready, stops accepting connections and allows requests
up to 10 seconds to finish within Kubernetes' 30-second termination grace period.
HTTP timeouts bound slow clients. Database readiness checks can be added later
without making liveness depend on external systems.

## Build and run the container

With Docker Desktop running Linux containers, from the repository root:

```powershell
docker build --pull -t sample-service:0.1.0 apps/sample-service
docker run --rm --name sample-service --read-only --cap-drop=ALL --security-opt=no-new-privileges --memory=128m --cpus=0.5 -p 127.0.0.1:8080:8080 sample-service:0.1.0
```

The Debian slim Node.js LTS image balances compatibility and size. The build copies
only the package metadata and source; a builder stage is unnecessary without
compilation or dependencies. The process uses the image's `node` user (UID 1000),
exec-form startup and an unprivileged port. The Docker health check is useful
outside Kubernetes; Kubernetes uses its own probes. No writable filesystem is needed.
The base tag receives security patches via `--pull`; this means builds are repeatable
but not bit-for-bit reproducible. Application images are now promoted by digest, so
what runs is exactly what was scanned; pinning and refreshing the *base* image digest
is still outstanding. Dependabot proposes dependency updates.

## Inspect or deploy the Helm chart

```powershell
helm lint --strict platform/helm/sample-service
helm template sample platform/helm/sample-service --namespace idp-dev
```

For an existing **development** cluster, first make the image available to its
container runtime: load the local image using your cluster tool, or push it to a
reachable registry and override `image.repository` and `image.tag`.

```powershell
kubectl apply -f platform/kubernetes/namespace.yaml
helm upgrade --install sample platform/helm/sample-service --namespace idp-dev --wait --timeout 180s
kubectl rollout status deployment/sample-sample-service -n idp-dev
kubectl port-forward -n idp-dev svc/sample-sample-service 8080:80
```

The chart default is the local `sample-service:0.1.0`. `values-dev.yaml` now carries
environment shape only; the image identity lives in
[`gitops/environments/dev/sample-service.yaml`](gitops/environments/dev/sample-service.yaml)
and reaches the chart through `image.digest`, which takes precedence over
`image.tag`. To deploy a specific image by hand, append `--set
image.repository=REGISTRY/sample-service --set image.digest=sha256:...`. For a
private registry, configure access with `imagePullSecrets` using a pre-existing
secret; ECR in this account needs none, because the node role can pull. Never put
registry credentials in values files.

**Why Helm:** one reusable chart is the future service template's deployment
contract. Values expose images, replicas, resources, Service port and pull secrets.
Two replicas and a zero-unavailable rolling update improve continuity; a soft node
spread preference also permits small local clusters. The defaults reserve 100m CPU
and 64Mi RAM per pod, capped at 500m/128Mi; these are starting budgets to tune with
measurements. Startup probes protect boot, readiness controls traffic, and liveness
detects an unhealthy process. Pods are non-root, use a read-only filesystem, drop
all capabilities, apply RuntimeDefault seccomp, and do not mount API credentials.
The bootstrap namespace enforces Kubernetes' restricted Pod Security profile pinned
to v1.35, matching EKS. For older local clusters, set that label to their version.

A ClusterIP Service keeps this unauthenticated sample internal. TLS, ingress,
network policy, disruption budgets and autoscaling arrive once their controllers
and operational requirements are established. Replica count alone is not an SLA.
Generated Kubernetes resource names include both release and chart names to allow
multiple installations; the `sample` release creates `sample-sample-service`.

## Terraform foundation

Terraform 1.10+ is required for the future S3 native locking setup; CI uses 1.14.5.
The AWS provider is constrained to major version 6 and the committed lockfile pins
the resolved release. Initial validation needs network access to download it,
but no AWS account or credentials:

```powershell
terraform fmt -check -recursive infrastructure/terraform
terraform -chdir=infrastructure/terraform/environments/dev init -backend=false -input=false -lockfile=readonly
terraform -chdir=infrastructure/terraform/environments/dev validate
```

The root composes two local modules, keeping cloud concerns out of the application
chart. Explicit resources make the learning project inspectable without another
module abstraction. Networking provides a dedicated /16 VPC, two public and two
private /24 subnets across two AZs, an internet gateway and one NAT gateway.
Workers receive no public IPs. Subnet tags prepare for later load balancer discovery.
**One NAT gateway is a development cost tradeoff:** it creates an AZ dependency and
can incur cross-AZ transfer charges; production needs per-AZ NAT or an evaluated
private endpoint design. VPC flow logs and endpoint restrictions are later hardening.

EKS defaults to Kubernetes 1.35, a private API endpoint and two `t3.medium`
AL2023 workers, with group bounds of two to four. No autoscaler is installed, so
the maximum is a bound rather than a scaling trigger. The managed node group
simplifies patching; its launch template encrypts gp3 root disks and requires
IMDSv2 with hop limit 1. All control-plane log types have 30-day retention.
The cluster uses API-based access entries with no implicit creator administrator;
an explicit existing IAM role receives administrator access. Narrow developer RBAC
comes later.

**Workers default to spot capacity.** Spot is roughly 70% cheaper, which is what
makes an always-available portfolio cluster affordable, and the tradeoff is that a
node can be reclaimed at two minutes notice. Two comparable instance types are
listed so the request draws from a wider capacity pool, and `max_size` leaves
headroom for replacements. Set `capacity_type = "ON_DEMAND"` before a live demo if
a reclaimed node would be disruptive.

Networking and DNS run as **explicitly versioned managed add-ons** rather than the
unversioned components EKS installs at bootstrap: `vpc-cni`, `kube-proxy`,
`eks-pod-identity-agent`, `coredns` and `aws-ebs-csi-driver`. Putting the version in
state turns an upgrade into a reviewable plan change instead of silent drift.
Versions resolve at plan time from `aws_eks_addon_version` rather than being
hardcoded, because a pinned version may not exist in every region or Kubernetes
release. Ordering is explicit: CNI and kube-proxy attach to the control plane, while
CoreDNS and the CSI driver are scheduled workloads that wait for the node group.

The EBS CSI controller gets its permissions through **EKS Pod Identity**, not the
node role, so a compromised workload cannot manage cluster storage. Pod Identity is
preferred over IRSA here because it needs no OIDC provider, no certificate
thumbprint and no trust policy rewrite when the cluster is replaced. Phase 6 extends
the same mechanism to application workloads. CNI permissions still use the node
role.

## Remote state and CI identity

`environments/bootstrap` is applied once, by an administrator, before anything else.
It creates the state bucket and the identities CI uses, so it is the only root that
cannot itself run through CI.

The **state bucket** is versioned, encrypted, public-access-blocked and rejects
plaintext HTTP through a bucket policy, because S3 permits it by default. Locking
uses S3 native `use_lockfile` rather than a DynamoDB table, which removes a resource
and its cost from the design; this is why Terraform 1.10+ is required. The bucket
carries `prevent_destroy`: state is not reproducible from the repository, so losing
it is worse than losing the infrastructure it describes. Old versions expire after
90 days, retaining ten, so recovery stays possible without unbounded storage.

Bootstrap keeps **local state** deliberately. Storing its state in the bucket it
creates would be circular, and it describes only a bucket and two roles.

CI authenticates with **GitHub OIDC**, so there are no AWS access keys in GitHub to
leak or rotate. Two roles separate reading from writing:

- `idp-terraform-plan` — `ReadOnlyAccess`, assumable from pull requests and `main`.
  It also gets write access to the state prefix, because S3 native locking writes a
  lock object beside the state and a strictly read-only role cannot plan.
- `idp-terraform-apply` — assumable **only** from the `aws-dev` GitHub Environment.
  The human approval gate lives on that environment, and the trust policy enforces
  it, so a workflow that skips the gate cannot obtain write credentials at all.

The apply role uses `PowerUserAccess`, which covers VPC, EKS, EC2, ECR and S3 while
excluding IAM, so its blast radius stops short of the account's own permission
model. EKS still needs to create roles, so that is granted back narrowly: only for
role names under the `idp-` prefix, plus the specific service-linked roles EKS,
node groups and spot require. The subject claim is matched against this exact
repository rather than a wildcard, since that claim is the only thing separating
these roles from any other repository on GitHub.

## Image registry

`modules/ecr` creates one repository per service. **Tags are immutable**, so a
deployed digest can never be silently replaced — that is what makes the image
reference recorded in Git trustworthy now that Argo CD drives deployments.
Scan-on-push gives a registry-side vulnerability view independent of the
CI-side Grype gate. A lifecycle policy expires untagged layers after seven days and
keeps twenty tagged images, bounding storage cost while leaving rollback targets.
`force_delete` is off, so destroying a repository that still holds images requires a
conscious decision rather than silently deleting published artefacts.

The registry is a separate module from the cluster because images outlive any single
cluster; the environment can be destroyed and rebuilt without republishing.

## Provisioning

Follow the [Phase 2 runbook](docs/phase-2-plan.md) for the full sequence. In short:
apply `environments/bootstrap`, record its outputs as GitHub secrets, create the
`aws-dev` environment with a required reviewer, then initialise `environments/dev`
with `terraform init -backend-config=backend.hcl`.

Before applying, choose private operator connectivity (VPN or a VPC runner) or allow
only your trusted public IPv4 `/32` through `public_access_cidrs`; the input
validation rejects `/0`. State, tfvars, plans and backend configuration are
gitignored because they can hold account-specific or sensitive values; lockfiles are
committed.

**This environment bills by the hour whether or not anything is deployed to it** —
roughly $132/month on spot, $181/month on-demand, before usage-based charges. The
[teardown runbook](docs/teardown.md) has an itemised breakdown and an ordered destroy
procedure. Destroy order matters: load balancers and volumes created by Kubernetes
are invisible to Terraform, and a stranded load balancer keeps billing and blocks
VPC deletion.

## Continuous integration

Pull requests, pushes to `main`, and manual dispatch run three jobs:

1. **Test:** locked install, syntax checks, HTTP tests and `npm audit` for high or
   critical dependency findings. There are currently no application dependencies.
2. **Configuration:** strict Helm lint, chart rendering, Terraform formatting,
   provider initialization with the lockfile, and Terraform validation without AWS.
3. **Container:** after both pass, build a commit-tagged image, test it with the same
   read-only/capability/resource restrictions, verify graceful shutdown, then scan
   image packages with Anchore/Grype. High and critical vulnerabilities fail the job.
   On `main` only, the job then assumes the publish role, pushes that same image to
   ECR and records its digest. Re-running a build for an already published commit
   reuses the published digest rather than failing against the immutable tag.
4. **Promote:** rewrites `gitops/environments/dev/sample-service.yaml` with the new
   digest and opens a pull request containing that single change. It is the only job
   that keeps checkout credentials, and the only one that can write to the repository.

The configuration job also asserts that a set digest reaches the rendered container
image reference, and exercises the promotion script's digest validation. A promotion
mechanism that silently rendered a tag would look identical in review.

A second workflow, `terraform.yaml`, handles infrastructure. Pull requests touching
`infrastructure/terraform/**` get a plan posted as a comment; merging to `main` runs
the apply job, which pauses on the `aws-dev` environment until a reviewer approves.

Plan and apply are separate jobs with separate AWS roles, so a pull request from a
fork or an untrusted branch can never hold write credentials. The apply job plans
and applies in the same step rather than passing a saved plan between jobs: the plan
being applied is the one just computed against current state, and no plan file — which
can contain resource values — is uploaded as an artifact. Concurrency is serialised
rather than cancelled, because cancelling mid-apply leaves a held state lock.

Actions are pinned to full commit IDs, tokens have read-only repository permissions
by default, checkout does not retain credentials, and jobs have timeouts. `id-token:
write` is granted only in the jobs that authenticate to AWS, and the publish steps
are additionally gated on the event being a push to `main`, so a pull request — from
a fork or otherwise — builds and scans the image but can never publish it.
Configure `test`, `configuration`, and `container` as required branch-protection
checks after creating the GitHub repository. Image scans depend on the vulnerability
database and may reveal new findings without source changes; refresh the base image
or review a narrowly justified exception instead of disabling the gate. These are
basic dependency/image checks, not a full security audit or IaC policy evaluation.

## GitOps delivery

Argo CD reconciles `main` into the cluster. The [Phase 3 runbook](docs/phase-3-plan.md)
has the installation and delivery procedure; this is what it is made of.

**Installation** is a pinned upstream release, not `stable`, so no unrelated apply
can move the control plane to a new minor version:

```powershell
kubectl kustomize platform/argocd/install | kubectl apply -f -
kubectl apply -f platform/kubernetes/namespace.yaml
kubectl apply -f platform/argocd/project.yaml
kubectl apply -f platform/argocd/applications/root.yaml
```

**An app-of-apps** watches `platform/argocd/applications`, so adding a service is a
commit rather than a `kubectl apply`. It excludes its own definition: a root
Application that manages itself can prune the controller's entry point during a bad
sync. The AppProject and root are therefore applied once by hand.

**The service Application has two sources.** The chart supplies how the workload runs;
`gitops/environments/dev/sample-service.yaml`, referenced through Argo CD's `$values`
alias, supplies which image runs. That split is the point: CI's promotion job writes
deployment state and cannot touch the probes, resource limits or security context it
is deploying under.

**Sync is automated with self-heal and prune,** which is what makes Git the source of
truth rather than a record of intent — a revert is a deployment, with no operator
action in between. Scaling the Deployment by hand is reverted by the controller. Do
not manage the same release with both manual Helm and Argo CD.

Before using the manifests, push this project to GitHub and replace `OWNER` in
`project.yaml` and in both files under `platform/argocd/applications/`; the AppProject
restricts sources to that exact repository URL. Configure Argo CD repository access if
the repository is private. Until the first promotion, deployment state names
`PENDING_FIRST_PROMOTION` and is intentionally non-deployable.

The Argo CD server is not exposed; reach it with `kubectl -n argocd port-forward
svc/argocd-server 8080:443`. That avoids paying for a load balancer and avoids
publishing an admin interface during development.

## Validation and next work

See [local verification](docs/validation.md), the [Phase 1 plan](docs/phase-1-plan.md),
the [Phase 2 runbook](docs/phase-2-plan.md), the [Phase 3 runbook](docs/phase-3-plan.md),
the [teardown runbook](docs/teardown.md) and the
[phase acceptance criteria](docs/roadmap.md).

Phase 2 and Phase 3 configuration is written and validates locally, but **nothing has
been applied to AWS and no image has been published**. The state bucket, roles,
registry, add-ons and spot node group are unverified against a real account until the
bootstrap and dev roots are applied. Argo CD's installation renders correctly and the
chart renders a promoted digest, but no cluster has reconciled it: rendering is not
admission, and a Synced Application is not a proven rollout. Terraform validation
checks configuration and provider schemas, not permissions, quotas, regional capacity
or successful provisioning.

The next milestone is Phase 4: a Backstage catalog and a service template that
scaffolds a repository wired to this delivery path. Prometheus, Grafana,
OpenTelemetry, External Secrets and Kyverno are intentionally roadmap items, not
empty services.

## References

- [Node.js release schedule](https://github.com/nodejs/Release): runtime lifecycle.
- [AWS EKS version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html): verify the selected Kubernetes version before provisioning.
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs): resource configuration.
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3): state storage and native locking.
- [Argo CD Application specification](https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/): Git source, Helm values and sync behavior.
- [Argo CD multiple sources](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/): the `$values` reference used to layer deployment state over the chart.
- [Argo CD cluster bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/): the app-of-apps pattern.
- [Configuring OpenID Connect in AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws): subject claims and trust policy conditions.
- [Anchore scan action](https://github.com/anchore/scan-action): image scan inputs and severity gate.
