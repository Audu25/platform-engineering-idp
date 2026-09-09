# Phase 1 implementation plan

The Desktop was inspected before implementation. No existing target repository
or applicable AGENTS.md instructions were found. Node.js, Git, Helm, Terraform,
Docker CLI, and kubectl are installed; Docker engine availability needs checking.

1. Create `platform engineering project/platform-engineering-idp` on the Desktop.
2. Implement a dependency-free Node.js API with separate liveness/readiness routes,
   structured logging, graceful shutdown, and native HTTP tests.
3. Package the service in a non-root image with a narrow build context.
4. Add a Helm chart with probes, resource bounds, secure pod settings and a Service.
5. Scaffold a development Terraform root with reusable network and EKS modules.
6. Add CI for tests, image build, dependency/image scans, Helm and Terraform checks.
7. Add namespace, scoped Argo CD project, and manually synced Application manifests.
8. Document architecture, local commands, setup placeholders, limitations and roadmap.
9. Run available local verification and record checks requiring Docker, GitHub or AWS.

No cloud provisioning, registry publishing, GitHub repository creation, or
installation into an existing Kubernetes cluster is part of this phase.
