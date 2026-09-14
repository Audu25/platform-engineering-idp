#!/usr/bin/env bash
# Promotes the image a service runs in one environment into the next.
#
# Only adjacent promotions exist: dev to staging, staging to production. There is
# no flag for dev to production, because "passed staging" has to be a property of
# the digest, not of the person running the command. check-platform.py enforces
# the same rule from Git history, so a hand-edited production file cannot skip it
# either.
#
# The image identity is copied verbatim — repository, tag and digest — so the
# bytes production runs are the bytes staging ran, not a rebuild of the same tag.
#
# Usage: platform/scripts/promote-environment.sh --service NAME --from ENV --to ENV
set -euo pipefail

service=""
from=""
to=""

usage() {
  echo "usage: $0 --service NAME --from dev|staging --to staging|production" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --service) service="${2:-}"; shift 2 ;;
    --from) from="${2:-}"; shift 2 ;;
    --to) to="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[ -n "${service}" ] && [ -n "${from}" ] && [ -n "${to}" ] || usage

# The service name becomes part of file paths, so it is validated before use.
if ! printf '%s' "${service}" | grep -Eq '^[a-z][a-z0-9-]{1,38}[a-z0-9]$'; then
  echo "invalid service name: ${service}" >&2
  exit 1
fi

case "${from}:${to}" in
  dev:staging|staging:production) ;;
  *)
    echo "only dev -> staging and staging -> production are allowed; production is reached through staging" >&2
    exit 1
    ;;
esac

root="$(cd "$(dirname "$0")/../.." && pwd)"
source_file="${root}/gitops/environments/${from}/${service}.yaml"
target_file="${root}/gitops/environments/${to}/${service}.yaml"

if [ ! -f "${source_file}" ]; then
  echo "${service} is not deployed to ${from}" >&2
  exit 1
fi

# The file format is written by promote-image.sh, so these fixed patterns are
# reading a format this repository controls rather than parsing arbitrary YAML.
repository="$(sed -n 's/^  repository: //p' "${source_file}" | head -n 1)"
tag="$(sed -n 's/^  tag: "\(.*\)"$/\1/p' "${source_file}" | head -n 1)"
digest="$(sed -n 's/^  digest: "\(.*\)"$/\1/p' "${source_file}" | head -n 1)"

if [ -z "${digest}" ]; then
  echo "${service} has no promoted digest in ${from}; there is nothing to promote" >&2
  exit 1
fi

current="$(sed -n 's/^  digest: "\(.*\)"$/\1/p' "${target_file}" 2>/dev/null | head -n 1 || true)"
if [ "${current}" = "${digest}" ]; then
  echo "${service} in ${to} already runs ${digest}; nothing to promote"
  exit 0
fi

"${root}/platform/scripts/promote-image.sh" \
  --file "${target_file}" \
  --repository "${repository}" \
  --tag "${tag}" \
  --digest "${digest}"

# The first promotion into an environment also needs something to deploy it.
# The Application is derived from the dev one with exactly four substitutions,
# so every environment's Application differs from dev's only where it must.
application="${root}/platform/argocd/applications/${service}-${to}.yaml"
if [ ! -f "${application}" ]; then
  template="${root}/platform/argocd/applications/${service}-dev.yaml"
  if [ ! -f "${template}" ]; then
    echo "no dev Application to derive ${service}-${to} from" >&2
    exit 1
  fi
  sed \
    -e "s/^  name: ${service}-dev\$/  name: ${service}-${to}/" \
    -e "s/values-dev\.yaml/values-${to}.yaml/" \
    -e "s#environments/dev/#environments/${to}/#" \
    -e "s/^    namespace: idp-dev\$/    namespace: idp-${to}/" \
    "${template}" > "${application}"
  echo "created ${application#"${root}/"}"
fi
