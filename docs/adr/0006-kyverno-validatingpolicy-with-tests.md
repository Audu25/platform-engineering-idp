# 0006. Admission policy as Kyverno ValidatingPolicy, tested in CI

- **Status:** Accepted
- **Date:** 2026-09-13
- **Phase:** 6, extended in 7

## Context

The platform's conventions — digest-pinned images, hardened pods, one identity per
service, no reading a neighbour's secrets — are only conventions until the API server
enforces them. Kyverno 1.19 offers `ClusterPolicy`, now deprecated, and
`ValidatingPolicy`, written in CEL like Kubernetes' own ValidatingAdmissionPolicy.
OPA Gatekeeper was the alternative, using Rego.

## Decision

Kyverno `ValidatingPolicy` in CEL, every policy scoped by namespace selector to the
workload namespaces and applied identically to all three environments. Policies are
tested with the Kyverno CLI against the chart rendered for every environment and
against deliberate violations. The suite also guards itself: CI requires every policy
to be shown to pass, fail and skip, and fails any run where an expectation was excluded
rather than evaluated.

## Consequences

- CEL policies are portable toward native ValidatingAdmissionPolicy if Kyverno is ever
  removed.
- The CLI has two behaviours that make a green run meaningless unless guarded against:
  it ignores namespace selectors without a `variables` file, and it grades an excluded
  resource as passing whatever result was declared. Both were found by negative
  controls; the guards exist because of them.
- Policy fails closed. Platform namespaces are excluded from Kyverno's webhook so the
  tools needed to repair admission keep working while it is down.
- Admission can check that a resource's wiring matches its label, not that the label
  is honest. That guarantee still comes from Git review.
