# Teardown runbook

This environment bills by the hour whether or not anything is deployed to it.
Tear it down between working sessions and rebuild from Terraform when needed.

## Estimated running cost

Approximate `eu-west-2` on-demand list prices for an idle cluster, excluding data
transfer. Confirm current prices before relying on these figures.

| Item | Spot profile | On-demand profile |
| --- | --- | --- |
| EKS control plane ($0.10/hr) | $73 | $73 |
| NAT gateway ($0.045/hr) | $33 | $33 |
| Public IPv4 address on the NAT | $4 | $4 |
| 2 x t3.medium workers | ~$20 | ~$69 |
| 2 x 20 GB gp3 root volumes | ~$2 | ~$2 |
| **Monthly total** | **~$132** | **~$181** |

CloudWatch control-plane logs, ECR storage and NAT data processing are usage
based and are additional. The single NAT gateway is the largest fixed cost after
the control plane; it is shared across both availability zones deliberately.

## Order of teardown

Kubernetes creates AWS resources that Terraform does not know about. Deleting the
cluster first strands them, and a stranded load balancer keeps billing and blocks
VPC deletion. Remove Kubernetes-owned resources first.

1. **Stop Argo CD reconciling.** Self-heal recreates anything deleted underneath it,
   so removing workloads before the Applications turns teardown into a loop.

   ```bash
   kubectl -n argocd delete application --all
   kubectl -n argocd get application            # must be empty before continuing
   ```

   The Applications carry `resources-finalizer.argocd.argoproj.io`, so deletion
   cascades to their workloads and only completes while the Argo CD controller is
   still running. Delete the Applications before the namespace, never after: a
   finalizer with no controller left to clear it blocks deletion indefinitely, and
   recovering means editing the finalizer out by hand.

2. **Remove workloads that own AWS resources.**

   ```bash
   kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer
   kubectl delete ingress --all --all-namespaces
   kubectl delete pvc --all --all-namespaces
   ```

   Wait until the load balancers and volumes are actually gone before continuing;
   deletion is asynchronous.

3. **Confirm nothing is left behind.**

   ```bash
   aws elbv2 describe-load-balancers --query 'LoadBalancers[?VpcId==`VPC_ID`].LoadBalancerArn'
   aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'
   aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].PublicIp'
   ```

   Unattached volumes and unassociated Elastic IPs both bill continuously.

4. **Destroy the environment.**

   ```bash
   terraform -chdir=infrastructure/terraform/environments/dev destroy
   ```

   Review the plan before confirming. Destroy takes roughly 15-20 minutes, most of
   it waiting on the node group and the control plane.

5. **Empty ECR if the repositories block deletion.** Repositories are created with
   `force_delete = false`, so a repository holding images fails to destroy. That is
   intentional: it forces a conscious decision before deleting published images.

   ```bash
   aws ecr batch-delete-image --repository-name idp-dev/sample-service \
     --image-ids "$(aws ecr list-images --repository-name idp-dev/sample-service --query 'imageIds[*]' --output json)"
   ```

   Deleting images destroys every rollback target. Keeping the repositories and
   destroying only the environment is usually the better trade: ECR storage for
   twenty small images costs cents per month, and the digests recorded in
   `gitops/` stay resolvable.

6. **Verify the account is quiet.** Check the Cost Explorer daily view filtered on
   `CostCentre=platform-idp` the following day. A resource missed today shows up as
   tomorrow's charge.

## What is deliberately not destroyed

The bootstrap stack survives `destroy` of the dev environment:

- The **state bucket** carries `prevent_destroy = true`. State is not reproducible
  from the repository, and an empty bucket costs effectively nothing.
- The **OIDC provider and Terraform roles** cost nothing and are required to
  rebuild. Deleting them means re-running bootstrap and re-creating GitHub secrets.

To remove the account entirely, remove the `prevent_destroy` lifecycle block,
empty the bucket including all object versions, then destroy the bootstrap root.

## Rebuilding

```bash
cd infrastructure/terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform apply
aws eks update-kubeconfig --region eu-west-2 --name idp-dev
kubectl get nodes
```

Then reinstall the delivery layer, which lives entirely in Git:

```bash
kubectl kustomize platform/argocd/install | kubectl apply -f -
kubectl apply -f platform/kubernetes/namespace.yaml
kubectl apply -f platform/argocd/project.yaml
kubectl apply -f platform/argocd/applications/root.yaml
```

Argo CD then restores the workloads from the digests recorded in `gitops/`, with no
republishing and no promotion needed: the rebuilt cluster runs the same image bytes
it ran before. Argo CD's own admin password and any UI-only settings are not in Git
and are recreated fresh.

State is preserved in S3, so a rebuild produces the same cluster name and
addressing. Node and load balancer addresses change; anything pinned to them
must be reconfigured.
