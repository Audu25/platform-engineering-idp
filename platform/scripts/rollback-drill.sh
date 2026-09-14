#!/usr/bin/env bash
# A recovery drill for the release path, run in a throwaway Git repository.
#
# The runbook's recovery step is "git revert the promotion". That instruction is
# only trustworthy if reverting actually restores the previous digest in the
# right environment and leaves the others alone, and if the promotion scripts
# refuse the shortcuts that would make recovery ambiguous. This drill performs a
# full release through every environment, ships a second release, recovers
# production from it, and checks every step. It runs in CI, so the runbook is
# tested on every change to the scripts it depends on.
#
# Usage: platform/scripts/rollback-drill.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

service=sample-service
first=sha256:1111111111111111111111111111111111111111111111111111111111111111
second=sha256:2222222222222222222222222222222222222222222222222222222222222222
registry=111122223333.dkr.ecr.eu-west-2.amazonaws.com/idp-dev/${service}

mkdir -p "${work}/platform/argocd"
cp -R "${root}/platform/scripts" "${work}/platform/"
cp -R "${root}/platform/argocd/applications" "${work}/platform/argocd/"
cp -R "${root}/gitops" "${work}/"
cd "${work}"
git init -q
git config user.name drill
git config user.email drill@example.invalid
# The drill compares file contents. A global line-ending conversion setting would
# only add noise here, so it is switched off for this throwaway repository.
git config core.autocrlf false
git add -A
git commit -qm "baseline"

digest_in() {
  sed -n 's/^  digest: "\(.*\)"$/\1/p' "gitops/environments/$1/${service}.yaml"
}

check() {
  local description="$1" actual="$2" expected="$3"
  if [ "${actual}" != "${expected}" ]; then
    echo "FAIL  ${description}: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
  echo "ok    ${description}"
}

refuses() {
  local description="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "FAIL  ${description}: the command succeeded" >&2
    exit 1
  fi
  echo "ok    ${description}"
}

release() {
  local digest="$1" tag="$2"
  platform/scripts/promote-image.sh --file "gitops/environments/dev/${service}.yaml" \
    --repository "${registry}" --tag "${tag}" --digest "${digest}" > /dev/null
  git commit -qam "Promote ${service} ${tag} to dev"
  platform/scripts/promote-environment.sh --service "${service}" --from dev --to staging > /dev/null
  git add -A && git commit -qm "Promote ${service} ${tag} to staging"
  platform/scripts/promote-environment.sh --service "${service}" --from staging --to production > /dev/null
  git add -A && git commit -qm "Promote ${service} ${tag} to production"
}

echo "== Shortcuts are refused"
refuses "production cannot be promoted from dev directly" \
  platform/scripts/promote-environment.sh --service "${service}" --from dev --to production
refuses "an environment with no digest has nothing to promote" \
  platform/scripts/promote-environment.sh --service "${service}" --from dev --to staging
refuses "a path-like service name is rejected" \
  platform/scripts/promote-environment.sh --service "../../etc" --from dev --to staging

echo "== First release reaches every environment"
release "${first}" first
check "dev runs the first release" "$(digest_in dev)" "${first}"
check "staging runs the first release" "$(digest_in staging)" "${first}"
check "production runs the first release" "$(digest_in production)" "${first}"

echo "== Promoting the same digest again changes nothing"
before="$(git rev-parse HEAD)"
platform/scripts/promote-environment.sh --service "${service}" --from staging --to production > /dev/null
check "a repeated promotion leaves the working tree clean" "$(git status --porcelain)" ""
check "and creates no commit" "$(git rev-parse HEAD)" "${before}"

echo "== Second release reaches every environment"
release "${second}" second
check "production runs the second release" "$(digest_in production)" "${second}"

echo "== Recovery: revert the production promotion"
git revert --no-edit HEAD > /dev/null
check "production is back on the first release" "$(digest_in production)" "${first}"
check "staging still runs the second release" "$(digest_in staging)" "${second}"
check "dev still runs the second release" "$(digest_in dev)" "${second}"

echo "== Recovery is itself reversible"
git revert --no-edit HEAD > /dev/null
check "reverting the revert restores the second release" "$(digest_in production)" "${second}"

echo "Drill passed."
