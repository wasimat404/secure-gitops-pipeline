# Secure GitOps Pipeline

A production-style GitOps pipeline that ships only scanned, signed container images to Kubernetes — with zero long-lived credentials anywhere in the system.

Built end-to-end on AWS EC2 + k3s as a learning project. Real bugs were fought, real fixes shipped. See [`docs/LESSONS.md`](docs/LESSONS.md) for the debugging journey.

## What it does

You push code. The rest happens automatically:git push
↓
GitHub Actions: build → Trivy scan → Cosign sign → push to GHCR
↓                            ↑
fails on HIGH/CRITICAL
↓
github-actions[bot] commits new image tag to k8s/kustomization.yaml
↓
ArgoCD sees the commit → pulls manifests → applies to cluster
↓
Pods start → External Secrets Operator pulls DB password from Vault
↓
App runs with credentials it never sees in any file
The interesting bit: **ArgoCD watches Git, not the registry.** The image tag in `k8s/kustomization.yaml` is only updated by CI *after* Trivy passes. So a vulnerable image cannot reach the cluster — the manifest pointing to it never gets written.

## Requirements satisfied

| Requirement | How |
|---|---|
| GitHub Actions builds + scans image | `.github/workflows/ci.yml`, 4-job pipeline with `needs:` chain enforcing scan-before-push |
| Trivy for vulnerability scanning | Fails build on HIGH/CRITICAL with fixes available; SARIF uploaded to GitHub Security tab; `.trivyignore` for documented exceptions |
| HashiCorp Vault for secrets | Vault stores DB credentials; pods authenticate via Kubernetes ServiceAccount tokens (no static Vault tokens anywhere) |
| ArgoCD deploys only clean images | The image tag in Git is the only source of truth; CI is the only writer; ArgoCD reads from Git |
| Zero hardcoded credentials | GitHub→GHCR via ephemeral `GITHUB_TOKEN`; pod→Vault via SA token; Vault→K8s via API server validation; nothing on disk |

## Tech stack

- **Container runtime:** Docker for builds, containerd (via k3s) for runtime
- **Kubernetes:** k3s on AWS EC2 (single-node)
- **CI:** GitHub Actions with OIDC for keyless signing
- **Image scanning:** Aqua Trivy
- **Image signing:** Sigstore Cosign (keyless, OIDC)
- **Secret management:** HashiCorp Vault (KV v2) + External Secrets Operator
- **Continuous Deployment:** Argo CD with Kustomize
- **Application:** Python Flask + gunicorn

## Project structure

.
├── app/                          # Flask app (reads DB creds from env vars)
├── Dockerfile                    # Single-stage python:3.11-slim, non-root user
├── .trivyignore                  # Documented CVE exceptions
├── .github/workflows/ci.yml      # Build → Scan → Sign → Push → Bump manifest
├── k8s/                          # Kubernetes manifests applied by ArgoCD
│   ├── namespace.yaml            # PSA restricted profile
│   ├── serviceaccount.yaml       # Identity for Vault auth
│   ├── deployment.yaml           # readOnlyRootFilesystem, dropped capabilities
│   ├── service.yaml              # ClusterIP
│   ├── external-secret.yaml      # SecretStore + ExternalSecret pulling from Vault
│   └── kustomization.yaml        # Image tag rewritten by CI
├── argocd/                       # ArgoCD configuration (applied once, manually)
│   ├── project.yaml              # Whitelist of allowed resource kinds
│   └── application.yaml          # Source of truth = Git
├── vault/                        # Vault bootstrap (one-time setup)
│   ├── policy.hcl                # Read-only policy for one secret path
│   └── k8s-auth-setup.sh         # Wires up the K8s auth method
└── docs/
├── ARCHITECTURE.md           # Trust boundaries, design decisions
├── SETUP.md                  # Reproducible setup walkthrough
└── LESSONS.md                # What broke, why, how I fixed it

## Quick start

See [`docs/SETUP.md`](docs/SETUP.md) for the full walkthrough. The short version:

1. Spin up a Kubernetes cluster (k3s on EC2 works; kind also works for fully local)
2. Install ArgoCD, Vault (dev mode), External Secrets Operator
3. Bootstrap Vault: enable K8s auth method, write the policy, create the role
4. Apply `argocd/project.yaml` and `argocd/application.yaml`
5. Push a commit. Watch CI gate it. Watch ArgoCD deploy it.

## What this does NOT do (yet)

Honest list of gaps, not pretending the project is more than it is:

- **No real database.** The DB credentials are real (read from Vault), but the app doesn't connect to anything. Wiring up Postgres + a rotating credential is a future Phase.
- **No admission policy.** A Kyverno or Sigstore policy controller could *require* a Cosign signature at admission time. Right now signature verification is "you can verify it offline" rather than enforced.
- **No HA Vault.** Vault runs in dev mode (in-memory, auto-unsealed, fixed root token). Real Vault needs HA storage, KMS-based auto-unseal, audit logging, TLS — that's its own project.
- **No multi-environment.** One namespace, one cluster. ApplicationSet would be the way to fan out to dev/staging/prod.
- **No runtime security.** Falco / Tetragon would catch behavior at runtime. Out of scope here.
- **Infrastructure provisioned by hand.** EC2 + security group set up via the AWS console. Phase 3 would Terraform it.

## Status

Working end-to-end. The pipeline gates real CVEs, ArgoCD reconciles after every commit, the running app reads its DB password from Vault via ESO. JSON proof:

```bash
$ curl -s localhost:8080/
{"app":"secure-gitops-demo","db_password_set":true,"db_user":"app_user","version":"0.1.0"}
```

`db_password_set: true` is the project's whole thesis: a credential the app needs, that no file in this repo contains.
