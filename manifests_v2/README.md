# OpenShift/Kubernetes Manifests for Microservice App

This directory contains Kubernetes manifests for deploying the microservice application to OpenShift, with full Kustomize support for managing multiple environments, CloudNativePG for PostgreSQL, and ArgoCD for GitOps.

## Directory Structure

```
manifests_v2/
├── kustomization.yaml              # Root kustomization (for local testing)
├── base/                           # Shared resources
│   ├── kustomization.yaml
│   └── network-policy.yaml
├── auth-service/                   # Authentication service
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
├── game-service/                   # Game statistics service
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
├── frontend/                       # React frontend
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── nginx-configmap.yaml
│   └── route.yaml
├── sealed-secrets/                 # Sealed Secrets documentation
│   ├── README.md                   # Setup guide
│   ├── seal-all-secrets.sh         # Helper script
│   └── example-sealed-secret.yaml  # Example format
├── argocd/                         # ArgoCD Application manifests
│   ├── dev-app.yaml                # Dev environment (auto-sync)
│   ├── staging-app.yaml            # Staging environment (manual sync)
│   └── prod-app.yaml               # Production environment (manual sync)
└── overlays/                       # Environment-specific configurations
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── postgres-cluster.yaml   # CNPG cluster (1 instance)
    │   ├── cnpg-secret-patch.yaml  # Links apps to CNPG secrets
    │   ├── sealed-dockerhub-secret.yaml
    │   ├── sealed-auth-service-secret.yaml
    │   └── sealed-game-service-secret.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── postgres-cluster.yaml   # CNPG cluster (2 instances)
    │   ├── cnpg-secret-patch.yaml
    │   ├── sealed-dockerhub-secret.yaml
    │   ├── sealed-auth-service-secret.yaml
    │   └── sealed-game-service-secret.yaml
    └── prod/
        ├── kustomization.yaml
        ├── namespace.yaml
        ├── postgres-cluster.yaml   # CNPG cluster (3 instances HA)
        ├── cnpg-secret-patch.yaml
        ├── hpa.yaml                # HorizontalPodAutoscaler
        ├── sealed-dockerhub-secret.yaml
        ├── sealed-auth-service-secret.yaml
        └── sealed-game-service-secret.yaml
```

## Prerequisites

1. **OpenShift CLI (oc)** or **kubectl** (v1.14+) installed
2. **CloudNativePG Operator** installed (see below)
3. **Sealed Secrets Controller** installed (for GitOps - see below)
4. **ArgoCD** installed for GitOps deployments
5. **Docker Hub credentials** (if using external registry)

---

## How Kustomize Works

Kustomize lets you reuse the same base manifests across different environments while customizing only what's different.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Kustomize Flow                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  overlays/dev/kustomization.yaml                                        │
│       │                                                                 │
│       ├── ../../base ─────────────► base/kustomization.yaml             │
│       │                                   └── network-policy.yaml       │
│       │                                                                 │
│       ├── ../../auth-service ────► auth-service/kustomization.yaml      │
│       │                                   ├── deployment.yaml           │
│       │                                   ├── service.yaml              │
│       │                                   └── configmap.yaml            │
│       │                                                                 │
│       ├── ../../game-service ────► game-service/kustomization.yaml      │
│       │                                   └── ...                       │
│       │                                                                 │
│       ├── ../../frontend ────────► frontend/kustomization.yaml          │
│       │                                   └── ...                       │
│       │                                                                 │
│       ├── namespace.yaml          (dev-specific)                        │
│       ├── postgres-cluster.yaml   (dev-specific)                        │
│       └── sealed-*.yaml           (dev-specific secrets)                │
│                                                                         │
│  All merged → Applied with dev namespace + dev image tags               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Base** | Shared manifests (auth-service/, game-service/, frontend/) |
| **Overlay** | Environment-specific customizations (overlays/dev/, staging/, prod/) |
| **namespace** | All resources deployed to a single namespace |
| **images** | Override image tags per environment |
| **patches** | Modify specific values (replicas, resources, etc.) |

---

## ArgoCD GitOps Deployment

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GitOps Flow                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Developer pushes code                                               │
│       │                                                                 │
│       ▼                                                                 │
│  2. CI builds & pushes image to Docker Hub                              │
│       │                                                                 │
│       ▼                                                                 │
│  3. CI triggers gitops-promote workflow                                 │
│       │                                                                 │
│       ▼                                                                 │
│  4. gitops-promote updates overlays/{env}/kustomization.yaml            │
│       │                                                                 │
│       ▼                                                                 │
│  5. ArgoCD detects Git change → shows "OutOfSync"                       │
│       │                                                                 │
│       ▼                                                                 │
│  6. Manual sync (staging/prod) or auto-sync (dev)                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### ArgoCD Applications

Three ArgoCD Applications are provided in `argocd/`:

| Application | Overlay | Sync Policy |
|-------------|---------|-------------|
| `microservice-app-dev` | `overlays/dev` | **Automated** - deploys on every Git push |
| `microservice-app-staging` | `overlays/staging` | **Manual** - requires clicking "Sync" |
| `microservice-app-prod` | `overlays/prod` | **Manual** - requires clicking "Sync" |

### Deploy ArgoCD Applications

```bash
# Apply all ArgoCD applications
kubectl apply -f manifests_v2/argocd/

# Or apply individually
kubectl apply -f manifests_v2/argocd/dev-app.yaml
kubectl apply -f manifests_v2/argocd/staging-app.yaml
kubectl apply -f manifests_v2/argocd/prod-app.yaml
```

### Sync Wave Order

All manifests include ArgoCD sync wave annotations for proper deployment ordering:

| Wave | Resources | Purpose |
|------|-----------|---------|
| -2 | Namespace | Must exist before all other resources |
| -1 | SealedSecrets, ConfigMaps, CNPG Cluster | Dependencies for applications |
| 0 | Deployments, Services, NetworkPolicies | Main application resources |
| 1 | Routes, HPA | Depends on deployments existing |

---

## CI/CD Integration

### GitHub Actions Workflows

The service CI/CD workflows automatically trigger GitOps promotions:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Service Workflow (auth-service-ci.yml, etc.)                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  BUILD JOB (on master push):                                            │
│    1. Test & Lint                                                       │
│    2. Build & Push image (:staging-{sha} and :dev tags)                 │
│    3. Trigger gitops-promote → updates dev overlay                      │
│                                                                         │
│  STAGING JOB (after build):                                             │
│    4. Trivy security scan                                               │
│    5. Re-tag image to :staging                                          │
│    6. Trigger gitops-promote → updates staging overlay                  │
│                                                                         │
│  PRODUCTION JOB (on git tag, e.g., auth/v1.0.0):                        │
│    7. Trivy security scan                                               │
│    8. Re-tag image to :v1.0.0 and :latest                               │
│    9. Trigger gitops-promote → updates prod overlay                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  GitOps Workflow (gitops-promote.yml)                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  1. Checkout repository                                                 │
│  2. kustomize edit set image {image}:{tag}                              │
│  3. Git commit & push to overlays/{env}/kustomization.yaml              │
│                                                                         │
│  Features:                                                              │
│  • Concurrency group prevents race conditions                           │
│  • Retry with rebase handles simultaneous updates                       │
│  • Manual trigger for ad-hoc promotions                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### Docker Hub Tags

After CI runs, Docker Hub contains these tags for each service:

| Tag | Created By | Purpose |
|-----|------------|---------|
| `:staging-{sha}` | Build job | Immutable build artifact |
| `:dev` | Build job | Latest dev deployment |
| `:staging` | Staging job | Latest staging deployment |
| `:v1.0.0` | Prod job | Versioned release |
| `:latest` | Prod job | Latest production release |

### Promotion Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Promotion Workflow                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Push to master                                                      │
│       │                                                                 │
│       ▼                                                                 │
│  2. CI builds image :staging-abc123 and :dev                            │
│       │                                                                 │
│       ▼                                                                 │
│  3. gitops-promote updates overlays/dev/kustomization.yaml              │
│       │                                                                 │
│       ▼                                                                 │
│  4. ArgoCD auto-syncs dev (automated sync policy)                       │
│       │                                                                 │
│       ▼                                                                 │
│  5. CI promotes to :staging tag                                         │
│       │                                                                 │
│       ▼                                                                 │
│  6. gitops-promote updates overlays/staging/kustomization.yaml          │
│       │                                                                 │
│       ▼                                                                 │
│  7. ArgoCD shows staging "OutOfSync" → Click Sync                       │
│       │                                                                 │
│       ▼                                                                 │
│  8. Test in staging ✓                                                   │
│       │                                                                 │
│       ▼                                                                 │
│  9. Create git tag: auth/v1.0.0                                         │
│       │                                                                 │
│       ▼                                                                 │
│  10. CI promotes to :v1.0.0 tag                                         │
│       │                                                                 │
│       ▼                                                                 │
│  11. gitops-promote updates overlays/prod/kustomization.yaml            │
│       │                                                                 │
│       ▼                                                                 │
│  12. ArgoCD shows prod "OutOfSync" → Click Sync                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Manual Promotion (GitHub UI)

You can also trigger promotions manually:

```
GitHub → Actions → "GitOps - Update Kustomize Overlay" → Run workflow

  Service:     [auth-service ▼]
  Image:       [badex/auth-service]
  Tag:         [v1.2.3]
  Environment: [dev | staging | prod ▼]

  [Run workflow]
```

---

## Sealed Secrets (GitOps Secret Management)

For true GitOps, secrets should not be stored in plain text in Git. We use Bitnami Sealed Secrets to encrypt secrets so they can be safely committed.

### How It Works

```
Plain Secret → kubeseal (encrypt) → SealedSecret → Git → Cluster → Secret
```

### Quick Setup

1. **Install Sealed Secrets Controller**:
   ```bash
   helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
   helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
   ```

2. **Install kubeseal CLI**:
   ```bash
   brew install kubeseal  # macOS
   ```

3. **Seal your secrets**:
   ```bash
   cd manifests_v2/sealed-secrets
   ./seal-all-secrets.sh dev
   ```

See `sealed-secrets/README.md` for the complete guide.

### Secrets to Seal

| Secret | Purpose | Sync Wave |
|--------|---------|-----------|
| `dockerhub-cred` | Pull images from Docker Hub | -1 |
| `auth-service-secret` | JWT signing key | -1 |
| `game-service-secret` | JWT verification key | -1 |

---

## CloudNativePG (CNPG) Database

CloudNativePG manages PostgreSQL databases declaratively. Each environment gets its own dedicated PostgreSQL cluster.

### Installing the Operator

```
OpenShift Console → Operators → OperatorHub → Search "CloudNativePG" → Install
```

### Database Architecture Per Environment

| Environment | Cluster Name | Instances | Storage |
|-------------|--------------|-----------|---------|
| Dev | `postgres-dev` | 1 | 5Gi |
| Staging | `postgres-staging` | 2 | 10Gi |
| Prod | `postgres-prod` | 3 (HA) | 50Gi |

### How CNPG Secrets Work

When CNPG creates a PostgreSQL cluster, it automatically generates secrets:

```
postgres-dev-app          # Application credentials (used by apps)
postgres-dev-superuser    # Superuser credentials
```

**These secrets are NOT SealedSecrets** - they're created by the CNPG operator at runtime. Our deployments reference them directly.

---

## Environment Comparison

| Feature | Dev | Staging | Prod |
|---------|-----|---------|------|
| Namespace | `microservice-app-dev` | `microservice-app-staging` | `microservice-app-prod` |
| App Replicas | 1 | 2 | 3 |
| PostgreSQL Instances | 1 | 2 | 3 (HA) |
| PostgreSQL Storage | 5Gi | 10Gi | 50Gi |
| Image Tag | `:dev` | `:staging` | `:v1.0.0` |
| Log Level | `debug` | `info` | `warning` |
| App HPA | No | No | Yes (3-10 pods) |
| ArgoCD Sync | Auto | Manual | Manual |

---

## Deployment Guide

### Step 1: Install Prerequisites

1. CloudNativePG Operator (via OperatorHub)
2. Sealed Secrets Controller
3. ArgoCD

### Step 2: Seal Secrets

```bash
cd manifests_v2/sealed-secrets
./seal-all-secrets.sh dev
./seal-all-secrets.sh staging
./seal-all-secrets.sh prod
```

### Step 3: Deploy ArgoCD Applications

```bash
kubectl apply -f manifests_v2/argocd/
```

### Step 4: Verify Deployment

```bash
# Check ArgoCD applications
argocd app list

# Check PostgreSQL cluster status
oc get cluster -n microservice-app-dev

# Check all pods
oc get pods -n microservice-app-dev

# Get application route
oc get route -n microservice-app-dev
```

---

## Common Commands

### Kustomize

```bash
# Preview manifests
kubectl kustomize manifests_v2/overlays/dev/

# Apply manifests directly (without ArgoCD)
kubectl apply -k manifests_v2/overlays/dev/

# Diff against cluster state
kubectl diff -k manifests_v2/overlays/prod/
```

### ArgoCD

```bash
# List applications
argocd app list

# Sync an application
argocd app sync microservice-app-staging

# Get application status
argocd app get microservice-app-prod
```

### PostgreSQL (CNPG)

```bash
# Check cluster status
oc get cluster -n microservice-app-dev

# Connect to database
oc exec -it postgres-dev-1 -n microservice-app-dev -- psql -U app -d gamedb

# View CNPG-generated secrets
oc get secret postgres-dev-app -n microservice-app-dev -o yaml
```

---

## Troubleshooting

### ArgoCD Shows "OutOfSync" But Won't Sync

```bash
# Check sync status
argocd app get microservice-app-dev

# Force refresh
argocd app refresh microservice-app-dev

# Check for sync errors
argocd app sync microservice-app-dev --dry-run
```

### Database Not Ready

```bash
# Check CNPG cluster status
oc get cluster postgres-dev -n microservice-app-dev

# Check CNPG operator logs
oc logs -n openshift-operators -l app.kubernetes.io/name=cloudnative-pg
```

### Application Can't Connect to Database

```bash
# Verify CNPG secret exists
oc get secret postgres-dev-app -n microservice-app-dev

# Check if apps are using correct secret reference
oc get deployment auth-service -n microservice-app-dev -o yaml | grep -A5 secretKeyRef
```

### Pods Stuck in Pending (Insufficient CPU/Memory)

```bash
# Check why pod is pending
oc describe pod <pod-name> -n microservice-app-dev | grep -A5 Events

# Check node capacity
oc describe nodes -l node-role.kubernetes.io/worker | grep -A10 "Allocated resources"
```

**Symptom**: `0/5 nodes are available: 2 Insufficient cpu`

**Solution**: Reduce resource requests in the overlay:
```yaml
# overlays/dev/kustomization.yaml
patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/resources/requests/cpu
      value: "10m"
  target:
    kind: Deployment
```

### No Writable /tmp Directory (CrashLoopBackOff)

**Symptom**:
```
FileNotFoundError: No usable temporary directory found in ['/tmp', '/var/tmp']
```

**Why**: OpenShift runs containers with `readOnlyRootFilesystem: true` by default. Apps that need temp files (Python/gunicorn, Java) will crash.

**Solution**: Add an emptyDir volume for `/tmp`:
```yaml
# In deployment.yaml
spec:
  template:
    spec:
      containers:
        - volumeMounts:
            - name: tmp-volume
              mountPath: /tmp
      volumes:
        - name: tmp-volume
          emptyDir: {}
```

### Health Probe Failures (404 or Connection Refused)

```bash
# Check probe status
oc describe pod <pod-name> | grep -A5 "Liveness\|Readiness"
```

**Symptom**: `Liveness probe failed: HTTP probe failed with statuscode: 404`

**Why**: The `/health` endpoint doesn't exist in your image, or the app isn't listening on the expected port.

**Solutions**:

1. **Add health endpoint to your app**:
   ```python
   @app.route('/health')
   def health():
       return {'status': 'healthy'}, 200
   ```

2. **Remove probes for dev** (in overlay):
   ```yaml
   - op: remove
     path: /spec/template/spec/containers/0/livenessProbe
   - op: remove
     path: /spec/template/spec/containers/0/readinessProbe
   ```

3. **Use TCP probe instead of HTTP**:
   ```yaml
   livenessProbe:
     tcpSocket:
       port: 8080
   ```

### Common Issues Quick Reference

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| `Pending` - Insufficient cpu | Resource requests too high | Reduce CPU/memory requests |
| `CrashLoopBackOff` - No temp directory | `readOnlyRootFilesystem: true` | Add emptyDir volume for `/tmp` |
| `CrashLoopBackOff` - Probe failed 404 | Missing `/health` endpoint | Add endpoint or remove probes |
| `CrashLoopBackOff` - Connection refused | App not listening on port | Check containerPort matches app |
| `ImagePullBackOff` | Missing registry credentials | Check `dockerhub-cred` SealedSecret |
| `SealedSecret` not decrypting | Wrong cluster key | Re-seal with current cluster's key |
| CNPG cluster not creating | Operator not installed | Install CloudNativePG via OperatorHub |
| ArgoCD stuck on health check | Waiting for resource health | Force sync or check sync-wave order |

---

## Cleanup

```bash
# Delete via ArgoCD
argocd app delete microservice-app-dev

# Or delete namespace directly (includes database!)
oc delete namespace microservice-app-dev
```

**Warning**: Deleting the namespace will delete the PostgreSQL cluster and all data!
