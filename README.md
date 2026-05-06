<div align="center">

# 🛡️ Secure GitOps Pipeline

### *Push code. A robot scans it. If it's clean, it ships itself.*
### *If it's not, it dies in the pipeline.*
### *The app reads its database password from Vault — a password that doesn't exist in this repo.*

[![GitHub Actions](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](.github/workflows/ci.yml)
[![Trivy](https://img.shields.io/badge/Scan-Trivy-1904DA?logo=aqua&logoColor=white)](https://trivy.dev)
[![Cosign](https://img.shields.io/badge/Sign-Cosign-0F172A?logo=sigstore&logoColor=white)](https://www.sigstore.dev)
[![Argo CD](https://img.shields.io/badge/Deploy-Argo_CD-EF7B4D?logo=argo&logoColor=white)](https://argo-cd.readthedocs.io)
[![Vault](https://img.shields.io/badge/Secrets-Vault-FFEC6E?logo=vault&logoColor=black)](https://www.vaultproject.io)
[![k3s](https://img.shields.io/badge/Kubernetes-k3s-FFC61C?logo=k3s&logoColor=black)](https://k3s.io)

</div>

---

## ✨ The 30-second pitch

You know that feeling where you push code to `main` and then *hope* nothing's wrong in production?

This pipeline removes the hoping.

A vulnerable image **structurally cannot reach the cluster** — not by policy, but by data flow. ArgoCD watches Git, not the registry. The image tag in `k8s/kustomization.yaml` is only updated by CI *after* Trivy passes. So if a scan fails, the manifest never updates, and the cluster keeps running the last known-good version.

That single property is the whole security thesis of the project.

> **🖼️ SCREENSHOT SLOT #1 — The "money shot"**
> *Screenshot: ArgoCD UI showing the green resource tree, all hearts green, "Synced + Healthy" status. This is the one screenshot that tells the whole story.*

---

## 🧠 How it actually works

```
┌──────────────┐       git push       ┌─────────────────┐
│  Developer   │─────────────────────▶│     GitHub      │
└──────────────┘                      └────────┬────────┘
                                               │ trigger
                                               ▼
                                     ┌──────────────────┐
                                     │ GitHub Actions   │
                                     │ ┌──────────────┐ │
                                     │ │ 1. Build     │ │
                                     │ │ 2. Trivy 🛑  │ │  ◀─── HIGH/CRITICAL = STOP
                                     │ │ 3. Sign+SBOM │ │
                                     │ │ 4. Push GHCR │ │  ◀─── ephemeral GITHUB_TOKEN
                                     │ │ 5. Bump tag  │ │
                                     │ └──────────────┘ │
                                     └────────┬─────────┘
                                              │ commit
                                              ▼
                                     ┌──────────────────┐
                                     │  Git (manifests) │  ◀─── source of truth
                                     └────────┬─────────┘
                                              │ ArgoCD watches
                                              ▼
                                     ┌──────────────────┐    ┌──────────────┐
                                     │     ArgoCD       │───▶│ Kubernetes   │
                                     └──────────────────┘    └──────┬───────┘
                                                                    │
                                                       ┌────────────┴────────────┐
                                                       ▼                         ▼
                                            ┌──────────────────┐         ┌─────────────┐
                                            │ External Secrets │         │  App Pods   │
                                            │     Operator     │         │  (Flask)    │
                                            └────────┬─────────┘         └──────┬──────┘
                                                     │ pulls                    │
                                                     ▼                          │
                                            ┌──────────────────┐                │
                                            │      Vault       │ ◀──────────────┘
                                            └──────────────────┘    pod proves
                                                                    identity via
                                                                    K8s SA token
```

> **🖼️ SCREENSHOT SLOT #2 — Pipeline run**
> *Screenshot: GitHub Actions tab showing the 4-job pipeline (Build → Trivy → Push/Sign → Bump). All green ticks.*

---

## 🔐 The "no hardcoded credentials" trick

This is the bit most projects hand-wave. Here's how it actually works:

**1. The pod has an identity badge.** Every Kubernetes pod runs as a `ServiceAccount`. The cluster automatically gives it a JWT token saying *"I am `secure-app/secure-app`."* It's like an employee badge — automatic, scoped, expires.

**2. Vault trusts the cluster's word.** During setup, I told Vault: *"This Kubernetes API server is real. If a pod shows up with a token that the cluster validates, I'll believe its claimed identity."*

**3. A policy maps identity to permissions.** *"Whoever holds the role `secure-app` can read **one secret** at one path. Nothing else."*

**4. At runtime, the chain runs itself.**
   - External Secrets Operator hands the pod's token to Vault
   - Vault asks Kubernetes "is this token real?" — Kubernetes says yes
   - Vault returns a 1-hour scoped token
   - ESO uses it to read the secret, writes it as a Kubernetes Secret
   - The pod reads the K8s Secret as env vars and starts

No password, no API key, no static token at any step. **Identity all the way down.**

```bash
$ curl -s localhost:8080/
{"app":"secure-gitops-demo","db_password_set":true,"db_user":"app_user","version":"0.1.0"}
```

That `db_password_set: true` is the project's whole thesis. The password came from Vault, traveled through three trust handshakes, and lives in this pod's environment — and **nothing in this repo contains it.**

> **🖼️ SCREENSHOT SLOT #3 — The proof**
> *Screenshot: terminal showing the curl response with `db_password_set: true`, plus a `git grep password` returning zero hits.*

---

## 🛠️ The stack

| Layer | Tool | Why |
|---|---|---|
| **App** | Python 3.11 + Flask + gunicorn | Smallest realistic web app |
| **Container** | Docker, `python:3.11-slim`, non-root | Hardened, minimal |
| **CI** | GitHub Actions + OIDC | No long-lived registry creds |
| **Scanning** | Aqua Trivy | Industry standard; SARIF + GitHub Security tab |
| **Signing** | Sigstore Cosign keyless | No private keys to manage |
| **SBOM** | Anchore SBOM Action | SPDX JSON, attached as attestation |
| **Registry** | GHCR | Free, integrated with Actions |
| **Cluster** | k3s on AWS EC2 | Lightweight, real Kubernetes |
| **CD** | Argo CD | The canonical GitOps tool |
| **Manifests** | Kustomize | Image tag rewriting at deploy time |
| **Secrets** | HashiCorp Vault (KV v2) | Industry standard secret store |
| **Secret syncing** | External Secrets Operator | GitOps-native (resources in Git, not sidecars) |
| **Pod security** | PSA `restricted`, `readOnlyRootFilesystem`, dropped caps | Defense in depth |

---

## 📁 Repo layout

```
.
├── app/                          → the Flask app
│   ├── app.py                    → reads DB creds from env vars
│   └── requirements.txt
├── Dockerfile                    → single-stage, non-root, minimal
├── .trivyignore                  → CVE exceptions with justifications
├── .github/workflows/ci.yml      → the brain (build → scan → sign → push → bump)
├── k8s/                          → what runs in the cluster
│   ├── namespace.yaml            → PSA restricted profile
│   ├── serviceaccount.yaml       → identity for Vault auth
│   ├── deployment.yaml           → 2 replicas, hardened pod spec
│   ├── service.yaml              → ClusterIP
│   ├── external-secret.yaml      → SecretStore + ExternalSecret
│   └── kustomization.yaml        → image tag rewritten by CI
├── argocd/                       → ArgoCD config (applied once, manually)
│   ├── project.yaml              → resource-kind whitelist
│   └── application.yaml          → "watch this repo, apply k8s/"
├── vault/                        → one-time Vault bootstrap
│   ├── policy.hcl                → read-only, one path
│   └── k8s-auth-setup.sh         → wires K8s auth method
└── docs/
    ├── ARCHITECTURE.md           → trust boundaries, design decisions
    ├── SETUP.md                  → reproduce it yourself
    └── LESSONS.md                → what broke and why
```

---

## 🏗️ Build steps (what we actually did)

The high-level journey, in the order it happened:

### Phase 1 — Foundation
1. Wrote the Flask app to read DB creds from environment variables (the "no hardcoded creds" rule starts at the app)
2. Wrote a hardened `Dockerfile` (non-root, minimal base, pinned versions)
3. Wrote the GitHub Actions pipeline with the **`needs:` chain** that enforces scan-before-publish
4. Wrote Kubernetes manifests with PSA restricted, dropped capabilities, read-only filesystem
5. Wrote ArgoCD `AppProject` (least-privilege whitelist) and `Application` (auto-sync, self-heal)
6. Wrote Vault policy + K8s auth bootstrap script
7. Wrote ESO `SecretStore` + `ExternalSecret`

### Phase 2 — Bring up the cluster
8. Launched EC2 (`villkube`) in AWS Sydney
9. Installed k3s (single command, ~60 seconds)
10. Installed ArgoCD via official manifest
11. Installed Vault via Helm (dev mode)
12. Installed External Secrets Operator via Helm
13. Bootstrapped Vault: enabled K8s auth method, wrote the policy, created the role, stored a sample DB password

### Phase 3 — Wire it up
14. Applied `argocd/project.yaml`
15. Applied `argocd/application.yaml`
16. Applied `k8s/namespace.yaml` manually (because we use `CreateNamespace=false` to keep PSA labels)
17. Watched ArgoCD reconcile, ESO sync from Vault, pods start
18. Verified `curl localhost:8080/` returned `db_password_set: true` 🎉

> **🖼️ SCREENSHOT SLOT #4 — kubectl outputs**
> *Screenshot: terminal showing `kubectl get pods`, `kubectl get externalsecret`, `kubectl get secret` — proving the chain.*

---

## 🐛 Problems I hit, and what they taught me

A non-exhaustive list of bugs that shipped and then got debugged. **This section is the most useful one in the repo** — following a tutorial when nothing breaks teaches you nothing.

| # | Bug | What it taught me |
|---|---|---|
| 1 | Pinned `aquasecurity/trivy-action@0.24.0` and `@0.28.0` — neither existed | Always verify versions, don't trust memory |
| 2 | `kustomization.yaml` referenced `../vault/external-secret.yaml` — kustomize refused to load it | Kustomize won't read files outside its own directory (security feature) |
| 3 | Wrote `external-secrets.io/v1beta1` — installed ESO had promoted to `v1` | API versions move, especially for newer projects |
| 4 | ArgoCD AppProject didn't whitelist `SecretStore` — sync failed silently | Whitelists are explicit; any new resource kind needs an entry |
| 5 | Distroless image had Python 3.11; my builder used 3.12 → `ModuleNotFoundError: gunicorn` | Distroless venv path must match runtime Python's exact version |
| 6 | Switched to `python:3.11-slim` → gunicorn crashed because `readOnlyRootFilesystem: true` blocked `/tmp` | When you lock down the filesystem, you have to mount `emptyDir` for tmp |
| 7 | ArgoCD kept fighting ESO over default fields (`conversionStrategy`, `decodingStrategy`, etc.) | When two controllers manage the same resource, use `ignoreDifferences` to declare a winner |
| 8 | The bump-manifest job committed to `k8s/` but `paths-ignore: ['k8s/**']` skipped CI runs | `paths-ignore` blocks empty-commit triggers; need a real change in a watched path |
| 9 | Two `images:` entries in `kustomization.yaml` (one keyed by `app`, one by full image name) | Kustomize matched the wrong one → tag stayed `placeholder` |
| 10 | Trivy found CVEs in `jaraco.context` and `wheel` (build-time deps) | Real teams don't fix every CVE — they document exceptions in `.trivyignore` with justifications |
| 11 | Confused villkube SSH session with my laptop terminal approximately every 20 minutes | Always check `hostname` before running anything destructive |

Full debugging journey with logs and fixes in [`docs/LESSONS.md`](docs/LESSONS.md).

> **🖼️ SCREENSHOT SLOT #5 — Trivy gating a CVE**
> *Screenshot: GitHub Actions log showing Trivy table output with a HIGH severity CVE flagged, and the pipeline failing the gate step. Proof the gate isn't decorative.*

---

## 🚀 Try it yourself

[`docs/SETUP.md`](docs/SETUP.md) walks through the whole thing. Two paths:

- **Local:** kind cluster on your laptop. Free. Needs ~4 GB free RAM.
- **AWS:** t3.small or t3.medium EC2. ~$0.50/day if you stop nightly. Closer to "real."

Estimated time: **30–45 minutes** if nothing breaks. **3 hours** if you're learning — which is honestly the more useful experience.

---

## 📊 Status

| Component | Status |
|---|---|
| CI pipeline (build → scan → sign → push → bump) | ✅ All 4 jobs green |
| Trivy gate | ✅ Catches HIGH/CRITICAL with fixes; allowlists documented |
| ArgoCD reconciliation | ✅ Auto-syncs, self-heals, all resources Healthy |
| Vault → ESO → app credential flow | ✅ Working, `db_password_set: true` |
| Pod hardening | ✅ PSA restricted, non-root, RO rootfs, dropped caps |
| Image signing | ✅ Cosign keyless, SBOM attested |

> **🖼️ SCREENSHOT SLOT #6 — Browser hitting the app**
> *Screenshot: Windows browser at `http://localhost:8080/` showing the JSON response with formatted output.*

---

## 🚧 What this does NOT do (yet)

I'd rather under-claim than oversell. Things this project does **not** include:

- ❌ A real database (the credential works, just doesn't connect to anything)
- ❌ Admission-time signature verification (Kyverno or Sigstore policy controller — would *enforce* what Cosign already proves)
- ❌ HA Vault with KMS unseal (we use dev mode — fine for learning, not for production)
- ❌ Multi-environment fan-out (one namespace, one cluster — `ApplicationSet` would solve this)
- ❌ Runtime security (Falco / Tetragon)
- ❌ Infrastructure-as-code (EC2 was clicked in the AWS console — Terraform is **Phase 3**)
- ❌ Network policies (cluster is flat — should restrict pod-to-pod and pod-to-Vault)

Each is its own learning project. They're on the list.

---

## 🗺️ Roadmap

- [ ] **Phase 3** — Terraform-ify the EC2 + security group + IAM
- [ ] **Phase 4** — Kyverno admission policy requiring valid Cosign signature
- [ ] **Phase 5** — Real Postgres, with Vault generating dynamic DB credentials
- [ ] **Phase 6** — `ApplicationSet` for multi-env (dev/staging/prod)
- [ ] **Phase 7** — Network policies + service mesh (Linkerd)

---

<div align="center">

### Built by [@wasimat404](https://github.com/wasimat404)

*Took about a day of focused work. Most of that was debugging.*
*Each bug taught me more than the working state ever could.*

⭐ If this helped you understand GitOps + secret management, drop a star.

</div>
