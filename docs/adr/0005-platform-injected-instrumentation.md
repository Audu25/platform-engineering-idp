# 0005. The platform injects OpenTelemetry instrumentation

- **Status:** Accepted
- **Date:** 2026-09-13
- **Phase:** 5, corrected in 7

## Context

Traces need an SDK in every process. If each service adds one, versions drift, some
teams never do it, and the sample service loses its property of having no dependencies.

## Decision

The OpenTelemetry Operator injects the Node.js SDK at admission into any pod carrying
the annotation the shared chart adds. `OTEL_SERVICE_NAME` is set by the chart to the same
string as the catalog entity, Argo CD Application and ECR repository. The injected init
container gets an explicit restricted security context from the Instrumentation resource.

## Consequences

- Every service is traced without a code change or a dependency, and the SDK version is
  upgraded in one place.
- Auto-instrumentation produces spans for inbound and outbound HTTP only. Spans around
  business logic still need code.
- The SDK version is now the platform's responsibility, and an operator upgrade can change
  every service's telemetry at once.
- Injection happens at admission, so it has to satisfy the restricted Pod Security
  Standard and Kyverno. Phase 5 relied on the operator inheriting the application
  container's security context; Phase 7 made it explicit after finding that assumption
  was fragile.
