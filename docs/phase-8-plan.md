# Phase 8: portfolio release

Phases 1-7 built the platform. Phase 8 makes it presentable honestly: a test that
runs the platform's core against a real Kubernetes API server, the reasoning behind
its decisions written down, a demonstration anyone can reproduce, and one place that
says what it costs, what it does not do, and how to take it down.

## What was built

1. **An end-to-end test in kind** — [`e2e-kind.sh`](../platform/scripts/e2e-kind.sh) and
   the `End-to-end` workflow. It proves on a real API server what the earlier phases
   could only render:
   - the service runs under the restricted Pod Security Standard
   - a non-root process reads its mounted secret, and a rotation reaches the file
     without a restart
   - a release whose image cannot be pulled leaves both replicas serving, and rolls back
   - production's autoscaler and disruption budget are accepted
   - Kyverno admits the chart in every environment, refuses every violation, and leaves
     platform namespaces alone
2. **Architecture decision records** — [ten of them](adr/README.md), each stating what
   forced the decision and what it costs.
3. **A demonstration guide** — [demo.md](demo.md): a local track that runs without AWS,
   and a cloud track through create, deploy, observe, break and recover.
4. **Operations in one place** — [operations.md](operations.md): costs, every
   limitation, and the teardown order.
5. **A documentation link check** — `check-platform.py` now fails on any relative link
   in the documentation that leads nowhere. A runbook with a dead link fails during the
   incident it was written for.
6. **A status table in the [roadmap](roadmap.md)** — per phase, what is built, what is
   verified and how, and what has not run.

## Decisions worth explaining

**The end-to-end test stops at the Kubernetes boundary.** It needs no cloud account, so
it can run on every relevant change. It therefore cannot prove anything about ECR, Pod
Identity, the External Secrets controller or Argo CD, and it does not pretend to: the
secret is created directly rather than by External Secrets, and deployment is by Helm
rather than by Argo CD. What it does prove is the half that rendering never could —
that the API server, Pod Security and Kyverno accept what the platform ships and refuse
what it forbids.

**Server-side dry run for admission.** Kyverno is tested with `kubectl apply
--dry-run=server`, which runs every admission webhook without creating anything and
without pulling images. That lets the test use the production-shaped, ECR-referenced
chart rather than a local image that the image policy would rightly refuse.

**No screenshots.** The roadmap asked for them. A screenshot of a portal or dashboard
that has never run would be fabricated evidence, and a portfolio built on verified
claims cannot include one. The evidence offered instead is [validation.md](validation.md),
where every claim names how it was checked, and every test suite has negative controls
showing it fails when what it guards is broken.

**Say what has not run, prominently.** Every phase's validation already listed what was
not verified. Phase 8 collects it into the roadmap's status table and the operations
guide, so no one has to read seven runbooks to learn that nothing has been applied to AWS.

## Acceptance criteria

| Criterion | Status |
| --- | --- |
| Reproducible create/deploy/observe/rollback demo | The local track reproduces deployment, admission, alerting and rollback without AWS. The cloud track is documented step by step and **has not been performed** |
| Documented costs | [operations.md](operations.md), itemised, with usage-based charges and the cost of a demo session |
| Documented limitations | [operations.md](operations.md), grouped by evidence, isolation, operations and access |
| Documented cleanup | [teardown.md](teardown.md), summarised in operations.md |
| End-to-end test | **Passed** in kind on a fresh cluster in 253 seconds, after fixing one platform defect and three harness defects its first runs found |
| Architecture records | [Ten ADRs](adr/README.md) |
| Screenshots | Deliberately absent, for the reason above |

## What would complete it

One thing, which needs an AWS account: **run the cloud track of the demo.** Its first
run is the first time anything meets AWS. Record what breaks in validation.md and fix it
before calling the platform done.

The end-to-end test is the argument for doing so. Its first runs against a real API
server found a platform defect that every offline check had accepted, and three ways its
own harness could have reported the wrong thing.
