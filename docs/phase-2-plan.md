# Phase 2 implementation plan and runbook

Phase 1 produced configuration that validates without an AWS account. Phase 2 makes
it applyable: remote state, CI identity, a registry, versioned cluster add-ons and a
gated apply workflow.

## What was built

1. **`environments/bootstrap`** — S3 state bucket (versioned, encrypted, TLS-only,
   public access blocked, `prevent_destroy`), the GitHub Actions OIDC provider, and
   two IAM roles: read-only `idp-terraform-plan` and gated `idp-terraform-apply`.
2. **`modules/ecr`** — per-service repositories with immutable tags, scan-on-push and
   a lifecycle policy bounding storage cost.
3. **`modules/eks/addons.tf`** — managed `vpc-cni`, `kube-proxy`,
   `eks-pod-identity-agent`, `coredns` and `aws-ebs-csi-driver`, with the EBS CSI
   controller authorised through EKS Pod Identity rather than the node role.
4. **Spot node group** — `capacity_type` and scaling bounds are variables; the dev
   default is spot across two comparable instance types.
5. **`.github/workflows/terraform.yaml`** — plan on pull requests, apply on `main`
   behind the `aws-dev` environment, authenticating with OIDC and no stored keys.
6. **Cost tags and [teardown runbook](teardown.md)** — `Owner` and `CostCentre` on
   every resource, and an ordered destroy procedure covering orphaned resources.

## Runbook

Run these once, in order. Steps 1-3 are local with administrator credentials;
everything after that runs through CI.

### 1. Create state and CI identity

```bash
cd infrastructure/terraform/environments/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_owner, owner, cost_centre
terraform init
terraform apply
terraform output -raw backend_hcl > ../dev/backend.hcl
```

Bootstrap keeps local state on purpose. It is applied once, it describes only the
state bucket and two roles, and putting its state in the bucket it creates would be
circular. `terraform.tfstate` is gitignored; keep a copy outside the repository if
you want to be able to modify the roles later without importing.

### 2. Configure GitHub

Record the outputs as repository secrets and variables:

```bash
cd infrastructure/terraform/environments/bootstrap
gh variable set AWS_REGION --body "eu-west-2"
gh secret set TF_STATE_BUCKET --body "$(terraform output -raw state_bucket)"
gh secret set AWS_PLAN_ROLE_ARN --body "$(terraform output -raw plan_role_arn)"
gh secret set AWS_APPLY_ROLE_ARN --body "$(terraform output -raw apply_role_arn)"
gh secret set PLATFORM_ADMIN_ROLE_ARN --body "arn:aws:iam::ACCOUNT:role/YOUR_ADMIN_ROLE"
```

Both Terraform jobs are guarded on `vars.AWS_REGION`, so until the variable is set
the workflow skips instead of failing. Setting it is what switches the workflow on.

Then create the **`aws-dev`** environment with a required reviewer, under
Settings > Environments. The apply role's trust policy names this environment, so
without it the apply job cannot obtain credentials at all. The role ARNs are held as
secrets rather than variables only to keep the account ID out of public logs.

### 3. Move the dev environment onto remote state

```bash
cd infrastructure/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # set admin_role_arn and owner
terraform init -backend-config=backend.hcl
```

If local state already exists, add `-migrate-state` and confirm the state object
appears in the bucket before deleting the local file.

### 4. Apply

Open a pull request touching `infrastructure/terraform/**`. The plan job comments
the plan; review it, merge, then approve the `aws-dev` environment when the apply
job requests it. To apply the first time without a pull request, use the workflow
dispatch trigger, or apply locally from step 3.

### 5. Verify against the acceptance criteria

```bash
aws eks update-kubeconfig --region eu-west-2 --name idp-dev
kubectl get nodes -o wide                      # private addresses only
kubectl -n kube-system get pods                # coredns and aws-node running
kubectl run dns-probe --rm -it --restart=Never --image=busybox:1.36 \
  -- nslookup kubernetes.default.svc.cluster.local
aws eks list-addons --cluster-name idp-dev
```

Private workers are confirmed by nodes having no public IP. DNS is confirmed by the
probe resolving the cluster service. State locking is confirmed by running two plans
at once: the second reports the lock held by the first.

## Deliberately out of scope

No Argo CD installation, image publishing or GitOps promotion: those are Phase 3.
There is no cluster autoscaler, so `max_size` is a bound rather than a scaling
trigger. There are no VPC endpoints, so all cluster egress traverses the NAT
gateway. Developer RBAC remains a single administrator access entry.
