# 0001. Deployment state lives in this repository

- **Status:** Accepted
- **Date:** 2026-09-09
- **Phase:** 3

## Context

GitOps separates what is deployed from the code that produces it. The conventional
way is a second repository holding manifests or values, with its own history and
access control, that CI writes to and Argo CD reads.

This project is also meant to be read. A reviewer should be able to clone one
repository and follow a change from source to cluster.

## Decision

Deployment state lives in `gitops/environments/<environment>/<service>.yaml` in this
repository. Argo CD reads it as a separate `$values` source from the chart, so the
separation of "how it runs" from "which bytes run" is preserved at the source level.
CI's promotion jobs write only to this directory, and `CODEOWNERS` reviews it like
infrastructure.

## Consequences

- One clone shows the entire path, and one pull request can be reviewed end to end.
- Application and deployment history are interleaved in one log. Tooling that needs
  deployment-only history filters by path, as the promotion history check does.
- Write access is scoped by path and review, not by repository permissions, which is
  weaker: anyone who can merge to `main` can change deployment state.
- Splitting it out later is a directory move and a `repoURL` change in each Argo CD
  Application. Nothing else depends on the two living together.
