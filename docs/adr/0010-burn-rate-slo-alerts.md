# 0010. Reliability alerts are multi-window burn-rate SLO alerts

- **Status:** Accepted
- **Date:** 2026-09-13
- **Phase:** 7

## Context

Phase 5 alerted on thresholds: error rate above 5%, p95 latency above a second. A
threshold pages for a two-minute blip and stays silent through a slow leak that spends
the month's error budget by Thursday. Both failures teach people to distrust alerts.

## Decision

Availability objectives per environment — 99.5% in production, 99% in staging, none in
dev — alerted by burn rate over paired long and short windows, following the SRE
workbook: 14.4× over 1h and 5m, 6× over 6h and 30m, and 3× over 1d and 2h as a ticket.
Pages require at least one request a minute. Staging raises tickets only. The rules are
unit-tested with promtool against synthetic traffic.

## Consequences

- An alert means the budget is genuinely being spent now, and it clears soon after the
  cause stops.
- Low-traffic services stay quiet unless traffic reaches the floor, so an outage of an
  almost unused service may not page. That is deliberate and visible in the tests.
- Objectives rest on Tempo span metrics. Building this found that Tempo had never been
  generating them, which is exactly the kind of silent gap alerts cannot catch about
  themselves; the telemetry-pipeline alerts from Phase 5 exist for the same reason.
- There is no latency objective yet, only availability.
