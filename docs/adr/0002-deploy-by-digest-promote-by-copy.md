# 0002. Deploy by digest; promote by copying the digest

- **Status:** Accepted
- **Date:** 2026-09-09, extended 2026-09-13
- **Phase:** 3, 7

## Context

CI scans an image before it is published. That scan only protects production if
production runs the scanned bytes. A tag can be moved to other bytes, and even with
immutable tags in ECR a tag names a build, not its content. Rebuilding the same
commit for a later environment produces different bytes whenever a base image moves.

## Decision

The chart deploys `repository@digest` whenever a digest is set. CI records the digest
of the image it scanned and pushed. Promotion between environments copies the
repository, tag and digest verbatim from the previous environment's file; nothing is
rebuilt. Kyverno refuses any service image not pinned by digest to the platform
registry.

## Consequences

- What runs in production is provably what ran in staging and what CI scanned.
- Rollback is a revert of one line: the previous digest is still in the registry
  because tags are immutable and retention keeps twenty images.
- Humans cannot read a digest. The tag is still written beside it for identification.
- Digests prove which bytes, not who built them. Signing and verification are a
  separate, still-missing step.
