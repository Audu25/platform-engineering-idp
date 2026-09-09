#!/usr/bin/env bash
# Rewrites a GitOps image file with a specific repository, tag and digest.
#
# The whole file is regenerated rather than patched in place: an in-place edit
# that silently matched nothing would promote an unchanged digest and look like
# a successful deployment.
set -euo pipefail

file=""
repository=""
tag=""
digest=""

usage() {
  echo "usage: $0 --file PATH --repository URL --tag TAG --digest sha256:HEX" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --file) file="${2:-}"; shift 2 ;;
    --repository) repository="${2:-}"; shift 2 ;;
    --tag) tag="${2:-}"; shift 2 ;;
    --digest) digest="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[ -n "$file" ] && [ -n "$repository" ] && [ -n "$tag" ] && [ -n "$digest" ] || usage

# A malformed digest would be written into the cluster's desired state and fail
# as an image pull error minutes later, so it is rejected here instead.
case "$digest" in
  sha256:*) ;;
  *) echo "digest must start with sha256:" >&2; exit 1 ;;
esac
if ! printf '%s' "${digest#sha256:}" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "digest must be sha256: followed by 64 lowercase hex characters" >&2
  exit 1
fi

mkdir -p "$(dirname "$file")"
cat > "$file" <<YAML
# Deployment state for sample-service in dev. Rewritten by the promotion job in
# .github/workflows/ci.yaml; edit by hand only to force a specific image.
#
# This file is the whole deployment interface: changing it is what deploys, and
# reverting the commit that changed it is what rolls back.
image:
  repository: ${repository}
  tag: "${tag}"
  digest: "${digest}"
YAML

echo "promoted ${repository}@${digest} (tag ${tag}) into ${file}"
