#!/usr/bin/env bash
# Tests the admission policies against two kinds of input.
#
# The platform's own chart, rendered fresh on every run: it must pass every
# policy, because a policy that rejects the chart the platform ships is broken
# no matter how well it catches everything else. And hand-written violations,
# each of which must fail the policy it targets.
#
# Rendering on every run rather than committing the output means a chart change
# that breaks a policy fails here, in the pull request that made it.
#
# Usage: platform/scripts/test-policies.sh
#        KYVERNO=/path/to/kyverno platform/scripts/test-policies.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tests="${root}/platform/security/tests"
rendered="${tests}/rendered"
kyverno="${KYVERNO:-kyverno}"
python="${PYTHON:-python3}"

# sha256 of the empty string: a well-formed digest that names no real image.
digest="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

mkdir -p "${rendered}"
# Every environment's values are rendered and tested, because each one turns on
# different chart features: autoscaling and disruption budgets exist only in
# staging and production, and each names its own role and secret prefix.
for environment in dev staging production; do
helm template sample-service "${root}/platform/helm/service" \
  --namespace "idp-${environment}" \
  --values "${root}/platform/helm/service/values-${environment}.yaml" \
  --set image.repository=111122223333.dkr.ecr.eu-west-2.amazonaws.com/idp-dev/sample-service \
  --set image.tag=0123456789ab \
  --set image.digest="${digest}" \
  --set-string aws.accountId=111122223333 \
  > "${rendered}/chart-${environment}.yaml"

# helm template omits metadata.namespace, and the policies select by namespace,
# so it is added here. Two Pods are derived from the Deployment: the template as
# written, and the template as the OpenTelemetry Operator leaves it after
# injecting its init container — the shape admission actually sees at runtime.
"${python}" - "${rendered}/chart-${environment}.yaml" "${rendered}/service-${environment}.yaml" "idp-${environment}" <<'PY'
import sys
import copy
import yaml

source, target, namespace = sys.argv[1], sys.argv[2], sys.argv[3]
documents = [d for d in yaml.safe_load_all(open(source, encoding="utf-8")) if d]
output = []
for document in documents:
    document["metadata"]["namespace"] = namespace
    output.append(document)
    if document["kind"] != "Deployment":
        continue
    template = document["spec"]["template"]
    pod = {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {
            "name": document["metadata"]["name"] + "-pod",
            "namespace": namespace,
            "labels": template["metadata"]["labels"],
        },
        "spec": copy.deepcopy(template["spec"]),
    }
    output.append(pod)

    instrumented = copy.deepcopy(pod)
    instrumented["metadata"]["name"] = document["metadata"]["name"] + "-instrumented"
    spec = instrumented["spec"]
    spec.setdefault("volumes", []).append(
        {"name": "opentelemetry-auto-instrumentation-nodejs", "emptyDir": {"sizeLimit": "200Mi"}}
    )
    # The operator's injection as the platform's Instrumentation configures it: an
    # image by tag from another registry, with an explicit restricted security
    # context. Every policy must admit it, pod security included.
    spec["initContainers"] = [{
        "name": "opentelemetry-auto-instrumentation-nodejs",
        "image": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.62.0",
        "command": ["cp", "-r", "/autoinstrumentation/.", "/otel-auto-instrumentation-nodejs"],
        "securityContext": {
            "allowPrivilegeEscalation": False,
            "readOnlyRootFilesystem": True,
            "runAsNonRoot": True,
            "capabilities": {"drop": ["ALL"]},
            "seccompProfile": {"type": "RuntimeDefault"},
        },
        "volumeMounts": [{
            "name": "opentelemetry-auto-instrumentation-nodejs",
            "mountPath": "/otel-auto-instrumentation-nodejs",
        }],
    }]
    output.append(instrumented)

with open(target, "w", encoding="utf-8", newline="\n") as handle:
    yaml.safe_dump_all(output, handle, sort_keys=False)
PY
rm -f "${rendered}/chart-${environment}.yaml"
done

output="$(mktemp)"
status=0
"${kyverno}" test "${tests}" --remove-color | tee "${output}" || status=$?

# The CLI grades a resource its policy excluded as passing, whatever result was
# declared for it. A policy whose namespace selector matched nothing - a typo, a
# renamed namespace - would therefore exclude every fixture and pass the whole
# suite while constraining nothing. This refuses that: every fixture expected to
# pass or fail must actually have been evaluated.
"${python}" - "${tests}/kyverno-test.yaml" "${output}" <<'SCOPE' || status=1
import sys
import yaml

test = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
expected = {}
for result in test.get("results") or []:
    for name in result.get("resources") or []:
        expected[(result["policy"], result["kind"], name)] = result["result"]

reasons = {}
for line in open(sys.argv[2], encoding="utf-8", errors="replace"):
    cells = [cell.strip() for cell in line.split("\u2502")]
    if len(cells) < 7 or not cells[1].isdigit():
        continue
    parts = cells[4].split("/")
    reasons.setdefault((cells[2], parts[-3], parts[-1]), set()).add(cells[6])

problems = []
for (policy, kind, name), result in sorted(expected.items()):
    seen = reasons.get((policy, kind, name))
    if seen is None:
        problems.append(f"{policy} {kind}/{name}: expected {result}, but the CLI reported nothing")
    elif result in ("pass", "fail") and "Excluded" in seen:
        problems.append(f"{policy} {kind}/{name}: expected {result}, but the policy never evaluated it")

if problems:
    print(f"\nScope check failed: {len(problems)} expectation(s) were never evaluated.")
    for problem in problems:
        print(f"  - {problem}")
    sys.exit(1)
evaluated = sum(1 for result in expected.values() if result in ("pass", "fail"))
print(f"\nScope check: all {evaluated} pass and fail expectations were evaluated, not excluded.")
SCOPE
rm -f "${output}"
exit "${status}"
