# Backstage

What the platform owns of its portal: configuration, catalog entities and the
service template. The Backstage app itself is not here.

## Why the app is not in this repository

`npx @backstage/create-app` generates a Node monorepo of several hundred files
that nobody reviews and that changes wholesale on every upgrade. Committing it
would bury this project's own code and make the diff of a platform change
unreadable. What is worth reviewing is the configuration and the template, so
that is what is version controlled here; the app is generated once and points at
these files.

The cost of that choice is honest: this repository cannot prove the portal
starts. It can prove the catalog is internally consistent and the template is
well formed, which is what `platform/scripts/check-platform.py` does in CI.

## Layout

| Path | What it is |
| --- | --- |
| `app-config.yaml` | Platform configuration merged over the generated app's own |
| `catalog/org.yaml` | Groups and users. Ownership resolves against this file |
| `catalog/systems.yaml` | The domain, the dev system and the infrastructure resources |
| `templates/node-service/` | The software template, its skeleton, and the platform change it proposes |

Component entities live beside the code they describe — `apps/sample-service/catalog-info.yaml`
for the reference service, and `catalog-info.yaml` at the root of every scaffolded
repository — so an entity moves and dies with its code rather than drifting in a
central list.

## Run it locally

```bash
npx @backstage/create-app@0.9.1 --path ../idp-portal
cd ../idp-portal
yarn install
```

Add the plugins this configuration expects. The Kubernetes and Argo CD panels are
what make an entity page worth opening; without them the catalog is a directory.

```bash
yarn --cwd packages/app add @backstage/plugin-kubernetes @roadiehq/backstage-plugin-argo-cd
yarn --cwd packages/backend add @backstage/plugin-kubernetes-backend @roadiehq/backstage-plugin-argo-cd-backend
```

Set the environment this configuration reads, then start with both configs:

```bash
export APP_BASE_URL=http://localhost:3000
export BACKEND_BASE_URL=http://localhost:7007
export ORG_NAME='Your Organisation'
export GITHUB_TOKEN=ghp_...              # repo + workflow scope, or a GitHub App
export AUTH_GITHUB_CLIENT_ID=...
export AUTH_GITHUB_CLIENT_SECRET=...
export SCAFFOLDER_AUTHOR_EMAIL=platform@example.com
export K8S_CLUSTER_URL=$(aws eks describe-cluster --name idp-dev \
  --query 'cluster.endpoint' --output text)
export ARGOCD_URL=http://localhost:8080
export ARGOCD_AUTH_TOKEN=...

yarn start --config ../platform-engineering-idp/platform/backstage/app-config.yaml
```

Replace `OWNER` in `app-config.yaml` and in the catalog files with the GitHub
account first, or every catalog location will 404.

## Before anyone else uses it

The local setup above is a single-user trial. A shared portal needs, at minimum:

- **Postgres instead of in-memory SQLite.** The current database disappears with
  the process and cannot be shared between replicas.
- **A GitHub App instead of a personal token.** A PAT carries one person's access
  and stops working when they leave.
- **GitHub organisation ingestion instead of `org.yaml`.** The static user in that
  file is a placeholder so ownership resolves; it is not an identity system.
- **`permission.enabled: true`.** Enforcing rules against a catalog with one
  placeholder user proves nothing, so it stays off until identity is real.

Hosting the portal in the cluster is deliberately not part of this phase: it needs
a database and secrets, and secrets arrive with External Secrets in Phase 6.
