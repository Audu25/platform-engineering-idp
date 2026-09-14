#!/usr/bin/env bash
# Unit-tests the platform's alert rules with promtool.
#
# The rules are shipped as PrometheusRule resources for the Prometheus Operator,
# but promtool reads plain rule files. The groups are extracted from each
# resource into a scratch file first, so the tests run against exactly the rules
# the cluster receives rather than a hand-maintained copy that could drift.
#
# Usage: platform/scripts/test-alerts.sh
#        PROMTOOL=/path/to/promtool platform/scripts/test-alerts.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tests="${root}/platform/observability/tests"
promtool="${PROMTOOL:-promtool}"
python="${PYTHON:-python3}"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

"${python}" - "${root}/platform/observability/manifests/slos/availability.yaml" "${scratch}/slo-rules.yaml" <<'EXTRACT'
import sys
import yaml

source, target = sys.argv[1], sys.argv[2]
rule = yaml.safe_load(open(source, encoding="utf-8"))
with open(target, "w", encoding="utf-8", newline="\n") as handle:
    yaml.safe_dump({"groups": rule["spec"]["groups"]}, handle, sort_keys=False)
EXTRACT

"${promtool}" check rules "${scratch}/slo-rules.yaml"
cp "${tests}/slo-availability.test.yaml" "${scratch}/"
cd "${scratch}"
"${promtool}" test rules slo-availability.test.yaml
