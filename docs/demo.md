# Demonstration

Two ways to see the platform work. The local one runs now, on a laptop, with no cloud
account. The cloud one is the full story — create, deploy, observe, break, recover —
and costs a dollar or two if torn down afterwards.

## Local: no AWS

Everything below runs against the repository and, for the last step, a kind cluster.

**Needs:** Python 3 with PyYAML, Helm 3.19, Terraform 1.14, the Kyverno CLI 1.19.1,
promtool 3.14, and for the final step Docker, kind 0.33 and kubectl.

### 1. The platform is internally consistent

```bash
python3 platform/scripts/check-platform.py .
```

```text
OK: 8 catalog entities, 2 groups, 1 registered service(s), 13 Argo CD application(s)
across 2 project(s), 6 admission policies, 3 environments, 0 promotion(s) traced through history.
```

This checks ownership in the catalog, the service template, that every environment's
deployment state has an Application deploying it to the right namespace, that every
admission policy is scoped and tested, that names agree across Terraform and Helm, and
that every promoted digest ran in the previous environment first.

### 2. Invalid manifests are refused

```bash
bash platform/scripts/test-policies.sh
```

```text
Test Summary: 188 tests passed and 0 tests failed
Scope check: all 36 pass and fail expectations were evaluated, not excluded.
```

The chart is rendered for all three environments and must pass every policy; nineteen
deliberate violations must each be refused; platform components in other namespaces must
be left alone. Open [`platform/security/tests/violations/pods.yaml`](../platform/security/tests/violations/pods.yaml)
to see what is refused and why.

### 3. Reliability alerts page when they should, and only then

```bash
bash platform/scripts/test-alerts.sh
```

Synthetic traffic drives the burn-rate rules: a production outage pages, the same
outage on almost no traffic does not, staging raises a ticket instead of a page, dev
raises nothing, and the page clears soon after errors stop.

### 4. A bad release is recovered

```bash
bash platform/scripts/rollback-drill.sh
```

```text
== Recovery: revert the production promotion
ok    production is back on the first release
ok    staging still runs the second release
ok    dev still runs the second release
Drill passed.
```

Two releases go through every environment in a throwaway repository, and reverting the
production promotion restores the previous digest without touching the others. This is
the runbook's recovery step.

### 5. The service runs, rotates a secret and survives a failed release

```bash
bash platform/scripts/e2e-kind.sh
```

On a kind cluster with the platform's namespaces and Pod Security settings, this runs
the sample service from the shared chart, reads its mounted secret as a non-root user,
rotates the secret and watches the file change without a restart, ships a release whose
image cannot be pulled and confirms both replicas keep serving, rolls it back, installs
the production shape, and finally installs Kyverno and has the real API server refuse
every violation. Delete the cluster afterwards with `kind delete cluster --name idp-e2e`.

If cluster creation times out, the Docker engine may still be on cgroup v1, which
Kubernetes 1.35 and later cannot run on. Pin an older node image:

```bash
KIND_NODE_IMAGE='kindest/node:v1.34.11@sha256:44e222ee2132dab25ff87301682f89eb82c7880ea3a1bf543bfe9708fd08d67d' \
  bash platform/scripts/e2e-kind.sh
```

## Cloud: create, deploy, observe, break, recover

Allow two to three hours. Each step names the runbook with the full procedure.

### 0. Stand it up

Apply bootstrap and the dev environment ([Phase 2](phase-2-plan.md)), install Argo CD
and the platform ([Phase 3](phase-3-plan.md)), and set up the observability, security
and environment layers ([Phases 5](phase-5-plan.md), [6](phase-6-plan.md),
[7](phase-7-plan.md)). Run three workers.

### 1. Create a service

In Backstage, choose **Node.js HTTP service** and fill in a name and owning team
([Phase 4](phase-4-plan.md)). The portal creates the repository, registers it in the
catalog and opens one pull request against this repository. Merge it: Terraform gains an
image repository, IAM roles and secrets for the service, and Argo CD gains an Application.

### 2. Deploy it through every environment

Merge a change to the new service. CI tests, scans and publishes the image, then opens a
promotion pull request for dev. Merge it and watch Argo CD sync. Then:

```bash
gh workflow run promote.yaml -f service=<name> -f target=staging
gh workflow run promote.yaml -f service=<name> -f target=production
```

Production waits for an Environment reviewer, then opens its own pull request.

### 3. Observe it

Send traffic, then in Grafana find the trace in Tempo, follow it to its logs in Loki,
and open **IDP / Service overview** for request rate, error rate and latency by
environment ([Phase 5](phase-5-plan.md)).

### 4. Break it

Commit a change that makes the service return errors on `/`, and promote it through to
production. Within minutes of real traffic, `SLOErrorBudgetBurnFast` fires for
`idp-production`.

### 5. Recover it

Follow the alert's runbook link to [Recovering a release](phase-7-plan.md#recovering-a-release):

```bash
git log --oneline -- gitops/environments/production/<name>.yaml
git revert <promotion commit>
```

Merge the revert. Argo CD restores the previous digest, error rate falls, and the alert
clears once the short window is clean.

### 6. Tear it down

Follow the [teardown runbook](teardown.md), then check Cost Explorer the next day. See
[operations](operations.md) for what it cost.
