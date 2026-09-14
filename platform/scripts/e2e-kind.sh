#!/usr/bin/env bash
# End-to-end test on a real Kubernetes API server, in kind.
#
# Everything before this proves configuration renders and policies evaluate. None
# of it proves that a pod actually starts under the restricted Pod Security
# Standard with a read-only root filesystem, that a non-root process can read a
# mounted secret, that a rotation reaches the file, or that the API server — not a
# CLI imitating one — refuses a bad manifest. This does, against the chart and
# policies in this repository.
#
# It deliberately stops short of AWS: no ECR, no Pod Identity, no External Secrets
# controller, no Argo CD. Those need an account and are covered by the runbooks.
#
# Usage: platform/scripts/e2e-kind.sh           (creates the kind cluster if absent)
#        KIND_CLUSTER=name platform/scripts/e2e-kind.sh
set -euo pipefail

# Git Bash rewrites arguments that look like POSIX paths into Windows paths before
# they reach native binaries, turning /var/run/... inside a container into
# C:/Program Files/Git/var/run/.... Container paths must reach kubectl untouched.
export MSYS2_ARG_CONV_EXCL="/var/run/"

root="$(cd "$(dirname "$0")/../.." && pwd)"
cluster="${KIND_CLUSTER:-idp-e2e}"
context="kind-${cluster}"
python="${PYTHON:-python3}"
image="sample-service:e2e"
chart="${root}/platform/helm/service"
digest="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
registry="111122223333.dkr.ecr.eu-west-2.amazonaws.com/idp-dev/sample-service"

kubectl() { command kubectl --context "${context}" "$@"; }
helm() { command helm --kube-context "${context}" "$@"; }
step() { printf '\n== %s\n' "$*"; }
ok() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

readyz() {
  local namespace="$1" port="$2" body=""
  kubectl -n "${namespace}" port-forward svc/sample-service "${port}:80" > /dev/null 2>&1 &
  local forward=$!
  for _ in $(seq 1 30); do
    if body="$(curl -fsS "http://127.0.0.1:${port}/readyz" 2> /dev/null)"; then
      break
    fi
    sleep 1
  done
  kill "${forward}" 2> /dev/null || true
  wait "${forward}" 2> /dev/null || true
  [ -n "${body}" ] || fail "sample-service in ${namespace} did not answer /readyz"
  ok "sample-service in ${namespace} answers /readyz with ${body}"
}

# --- cluster -----------------------------------------------------------------
step "Cluster"
# KIND_NODE_IMAGE pins the Kubernetes version. A Docker engine still on cgroup v1 —
# Docker Desktop on an older WSL2 kernel, for one — cannot start a kubelet from
# Kubernetes 1.35 onward, and cluster creation times out with no clear cause.
if ! command kind get clusters 2> /dev/null | grep -qx "${cluster}"; then
  command kind create cluster --name "${cluster}" --wait 180s ${KIND_NODE_IMAGE:+--image "${KIND_NODE_IMAGE}"}
fi
kubectl version > /dev/null
# The workload namespaces exactly as the platform defines them, including the
# restricted Pod Security Standard.
kubectl apply -f "${root}/platform/kubernetes/namespace.yaml" > /dev/null
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f - > /dev/null
# The chart renders SecretStores and ExternalSecrets. No controller reconciles
# them here, but the API server has to know the kinds to accept them.
kubectl apply -f "${root}/platform/security/tests/crds/" > /dev/null
ok "namespaces and secret CRDs in place"

step "Image"
docker build --pull --quiet --tag "${image}" "${root}/apps/sample-service" > /dev/null
command kind load docker-image "${image}" --name "${cluster}"
ok "built and loaded ${image}"

# --- the workload ------------------------------------------------------------
install() {
  local environment="$1"
  # External Secrets would create this Secret from AWS. Without AWS it is created
  # directly, which exercises everything from the Secret onward.
  kubectl -n "idp-${environment}" create secret generic sample-service-config \
    --from-literal=greeting=hello --dry-run=client -o yaml | kubectl apply -f - > /dev/null
  helm upgrade --install sample-service "${chart}" \
    --namespace "idp-${environment}" \
    --values "${chart}/values-${environment}.yaml" \
    --set image.repository=sample-service \
    --set image.tag=e2e \
    --set-string aws.accountId=111122223333 \
    --set observability.instrumentation="" \
    --wait --timeout 240s > /dev/null
}

step "The service runs under restricted Pod Security"
install dev
kubectl -n idp-dev rollout status deployment/sample-service --timeout=120s > /dev/null
ok "admitted by Pod Security and available: non-root, read-only root filesystem, no capabilities"
readyz idp-dev 18080

step "A mounted secret is readable by the non-root process and follows rotation"
# Polled rather than read once: the kubelet syncs Secret volumes on its own
# schedule, so on a reused cluster the file can still hold a previous run's value
# for up to a minute after the Secret is reset.
for _ in $(seq 1 60); do
  value="$(kubectl -n idp-dev exec deploy/sample-service -- cat /var/run/secrets/app/greeting)"
  [ "${value}" = "hello" ] && break
  sleep 5
done
[ "${value}" = "hello" ] || fail "expected the mounted secret to read 'hello', got '${value}'"
ok "uid 1000 reads the secret file through fsGroup"
restarts_before="$(kubectl -n idp-dev get pods -l app.kubernetes.io/name=sample-service \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{" "}{end}')"
kubectl -n idp-dev create secret generic sample-service-config \
  --from-literal=greeting=rotated --dry-run=client -o yaml | kubectl apply -f - > /dev/null
started=$(date +%s)
for _ in $(seq 1 60); do
  value="$(kubectl -n idp-dev exec deploy/sample-service -- cat /var/run/secrets/app/greeting)"
  [ "${value}" = "rotated" ] && break
  sleep 5
done
[ "${value}" = "rotated" ] || fail "the rotated value never reached the mounted file"
restarts_after="$(kubectl -n idp-dev get pods -l app.kubernetes.io/name=sample-service \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{" "}{end}')"
[ "${restarts_before}" = "${restarts_after}" ] || fail "pods restarted during rotation"
ok "the rotation reached the file in $(( $(date +%s) - started ))s with no restart"

step "A failed release keeps serving, and rolls back"
kubectl -n idp-dev set image deployment/sample-service api=sample-service:does-not-exist > /dev/null
sleep 30
available="$(kubectl -n idp-dev get deployment sample-service -o jsonpath='{.status.availableReplicas}')"
[ "${available}" = "2" ] || fail "available replicas fell to '${available}' during a failed rollout"
ok "both replicas stayed available while the new image failed to pull"
readyz idp-dev 18081
kubectl -n idp-dev rollout undo deployment/sample-service > /dev/null
kubectl -n idp-dev rollout status deployment/sample-service --timeout=120s > /dev/null
current="$(kubectl -n idp-dev get deployment sample-service -o jsonpath='{.spec.template.spec.containers[0].image}')"
[ "${current}" = "${image}" ] || fail "after rollback the image is '${current}'"
ok "rolled back to ${image}"

step "Production values: autoscaler and disruption budget accepted"
install production
bounds="$(kubectl -n idp-production get hpa sample-service -o jsonpath='{.spec.minReplicas}/{.spec.maxReplicas}')"
[ "${bounds}" = "3/6" ] || fail "expected autoscaler bounds 3/6, got '${bounds}'"
budget="$(kubectl -n idp-production get pdb sample-service -o jsonpath='{.spec.maxUnavailable}')"
[ "${budget}" = "1" ] || fail "expected maxUnavailable 1, got '${budget}'"
ok "HorizontalPodAutoscaler 3/6 and PodDisruptionBudget maxUnavailable=1"
readyz idp-production 18082

# --- admission ---------------------------------------------------------------
step "Admission policy on a real API server"
command helm repo add kyverno https://kyverno.github.io/kyverno --force-update > /dev/null
helm upgrade --install kyverno kyverno/kyverno --version 3.9.1 \
  --namespace kyverno --create-namespace \
  --values "${root}/platform/security/values/kyverno.yaml" \
  --wait --timeout 300s > /dev/null
kubectl apply -f "${root}/platform/security/policies/" > /dev/null

# Policies register asynchronously. Probe with a known violation until the API
# server refuses it, rather than sleeping for a guessed interval.
probe="${root}/platform/security/tests/violations/deployment.yaml"
enforcing=""
for _ in $(seq 1 60); do
  if output="$(kubectl apply --dry-run=server -f "${probe}" 2>&1)"; then
    sleep 5
  elif printf '%s' "${output}" | grep -q 'idp-images-from-platform-registry'; then
    enforcing=yes
    break
  else
    sleep 5
  fi
done
[ -n "${enforcing}" ] || fail "policies never began refusing the probe: ${output}"
ok "Kyverno is enforcing"

for environment in dev staging production; do
  # apply warns about objects Helm created without kubectl's annotation. Only a
  # refusal matters, so the output is kept for the failure message alone.
  if ! output="$(helm template sample-service "${chart}" \
    --namespace "idp-${environment}" \
    --values "${chart}/values-${environment}.yaml" \
    --set image.repository="${registry}" \
    --set image.digest="${digest}" \
    --set-string aws.accountId=111122223333 \
    | kubectl apply --dry-run=server --namespace "idp-${environment}" -f - 2>&1)"; then
    fail "the platform's own chart was refused in idp-${environment}: ${output}"
  fi
  ok "the rendered chart is admitted in idp-${environment}"
done

# Two fixtures borrow another service's identity. The API server's ServiceAccount
# admission refuses a pod naming an account that does not exist before any webhook
# runs, which proves nothing about policy. The accounts are created so that the
# refusal, if it comes, comes from Kyverno.
for account in payments pay; do
  kubectl -n idp-dev create serviceaccount "${account}" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
done

"${python}" - "${context}" "${root}/platform/security/tests" <<'ADMISSION'
import subprocess
import sys
from pathlib import Path

import yaml

context, tests = sys.argv[1], Path(sys.argv[2])


def dry_run(document):
    return subprocess.run(
        ["kubectl", "--context", context, "apply", "--dry-run=server", "-f", "-"],
        input=yaml.safe_dump(document), capture_output=True, text=True,
    )


failures = 0
for path in sorted((tests / "violations").glob("*.yaml")):
    for document in (d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if d):
        name = f"{document['kind']}/{document['metadata']['name']}"
        result = dry_run(document)
        message = result.stderr + result.stdout
        if result.returncode == 0:
            print(f"FAIL  {name} was admitted")
            failures += 1
        elif "PodSecurity" in message or "violates PodSecurity" in message:
            print(f"ok    {name} refused by Pod Security")
        elif "denied the request" in message:
            print(f"ok    {name} refused by Kyverno")
        else:
            print(f"FAIL  {name} failed for an unrelated reason: {message.strip()[:200]}")
            failures += 1

for document in (d for d in yaml.safe_load_all((tests / "out-of-scope.yaml").read_text(encoding="utf-8")) if d):
    name = f"{document['kind']}/{document['metadata']['name']}"
    result = dry_run(document)
    if result.returncode == 0:
        print(f"ok    {name} in {document['metadata']['namespace']} is admitted: policy leaves platform namespaces alone")
    else:
        print(f"FAIL  {name} was refused outside the workload namespaces: {(result.stderr + result.stdout).strip()[:200]}")
        failures += 1

sys.exit(1 if failures else 0)
ADMISSION

printf '\nEnd-to-end test passed. Delete the cluster with: kind delete cluster --name %s\n' "${cluster}"
