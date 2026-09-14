# Operating the platform

What it costs to run, what it does not do, and how to take it down. Each phase's
runbook has the detail; this is the whole picture in one place.

## What it costs

Approximate `eu-west-2` list prices for the full platform — all three environments,
the observability stack and the security layer — on the recommended three workers.
Confirm current prices before relying on these; they are arithmetic, not a bill.

| Item | Spot workers | On-demand workers | Notes |
| --- | --- | --- | --- |
| EKS control plane | $73 | $73 | $0.10 an hour, whether or not anything runs |
| NAT gateway | $33 | $33 | Plus $0.048 per GB processed, which includes image pulls |
| Public IPv4 address on the NAT | $4 | $4 | |
| 3 × t3.medium workers | ~$30 | ~$104 | Three are needed once every environment and the observability stack run |
| 3 × 20 GB gp3 root volumes | ~$6 | ~$6 | |
| Secrets Manager | ~$1.50 | ~$1.50 | $0.40 per secret per service per environment, plus refresh calls |
| **Monthly total** | **~$148** | **~$222** | Before usage-based charges |

Usage-based charges on top:

- **CloudWatch control-plane logs.** All five EKS log types are enabled, and audit logs
  grow with cluster activity. Disable `audit` and `authenticator` for long idle periods.
- **NAT data processing.** A first sync pulls several gigabytes of platform images,
  a few tens of cents. A cluster that repeatedly pulls large images costs more.
- **ECR storage.** Cents, bounded by the twenty-image retention policy.

Nothing in Phases 3 to 7 creates a load balancer or a persistent volume, so none of
Argo CD, the observability stack, Kyverno or External Secrets adds an AWS charge of its
own. Their cost is node capacity.

**A demonstration costs about a dollar.** At roughly $0.20 an hour on spot, a
three-hour session followed by a [teardown](teardown.md) is well under two dollars.
Leaving it running is what gets expensive.

## What it does not do

These are the limitations that matter, collected from every phase. None is hidden in a
runbook's small print; each is also stated where it arises.

### Evidence

- **Nothing has been applied to AWS.** Every Terraform root validates. None has run
  against an account, so permissions, quotas, regional capacity and add-on versions are
  unproven.
- **Only Kyverno has run in a cluster.** Argo CD, the observability stack, External
  Secrets and Backstage have been rendered and validated, never started.
- **The end-to-end test stops at the Kubernetes boundary.** It passed in kind: the service
  runs under restricted Pod Security, a secret rotates into the pod without a restart, a
  failed release rolls back, and admission policy refuses every violation. It does not
  exercise AWS, Argo CD or External Secrets.
- **There are no screenshots.** A screenshot of a portal or dashboard that never ran
  would be a fabrication. The evidence is in [validation.md](validation.md): what was
  checked, how, and what each negative control proved.

### Isolation

- **All environments share one cluster** ([ADR 0009](adr/0009-environments-as-namespaces.md)).
  A control-plane or node-group failure affects production and staging together.
- **There are no NetworkPolicies.** Any pod can reach any other pod and anything the
  NAT gateway reaches. Secrets are isolated between services; traffic is not.
- **Images are digest-pinned but not signed.** A digest proves which bytes were
  scanned, not who built them.

### Operations

- **Observability data is ephemeral.** Prometheus, Loki and Tempo keep 24 hours on pod
  storage and lose it on restart.
- **Alerts go nowhere.** Alertmanager has no receiver, deliberately, until someone owns
  one.
- **Rollback is manual.** An SLO page tells a person to revert; there is no automated
  rollback and no canary.
- **There is no latency objective,** only availability.
- **Secret values are not reproducible.** Terraform creates secrets empty by design
  ([ADR 0008](adr/0008-terraform-owns-secret-existence-not-values.md)); a rebuilt
  environment needs its values put back, and rotation is manual.

### Access and identity

- **Argo CD has one admin account and no SSO,** and is reached by port-forward.
- **Backstage runs locally,** with permissions off and a placeholder user until GitHub
  organisation ingestion is configured.
- **Development replicas are single.** Kyverno's admission controller runs one replica,
  so while it restarts nothing new is admitted into the workload namespaces.

### Before first use

Replace `OWNER` in the Argo CD projects, Applications, catalog and `CODEOWNERS`, and
`AWS_ACCOUNT_ID` in the environment values files. Create the `staging` and
`production` GitHub Environments, the latter with required reviewers.

## How to take it down

Follow the [teardown runbook](teardown.md). The order matters, and in short:

1. Delete the Argo CD Applications, so self-heal stops recreating what you remove.
2. Confirm Kyverno removed its webhooks, or nothing can be created in the workload
   namespaces again.
3. Remove anything that owns an AWS resource, and confirm no load balancers, volumes
   or addresses remain.
4. `terraform destroy` the environment.
5. Check Cost Explorer by `CostCentre` the next day.

The state bucket, OIDC provider and CI roles survive on purpose: they cost nothing and
are needed to rebuild. Everything else returns from Git, except secret values.
