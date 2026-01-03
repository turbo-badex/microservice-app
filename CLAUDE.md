# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GameHub is a microservices-based gaming platform deployed on OpenShift/Kubernetes with GitOps via ArgoCD.

**Architecture:**
```
Frontend (React:3000) → Auth Service (Flask:8080) → PostgreSQL (CNPG)
                     → Game Service (Flask:8081) → PostgreSQL (CNPG)
```

## Common Commands

### Local Development

```bash
# Start all services (PostgreSQL, auth-service, game-service, frontend)
./start-local.sh

# Stop all services
./stop-local.sh

# Test local services
./test-local.sh
```

### Backend Services (auth-service, game-service)

```bash
cd auth-service  # or game-service

# Setup
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Run
export POSTGRES_HOST=localhost POSTGRES_DB=gamehub POSTGRES_USER=user POSTGRES_PASSWORD=password
python app.py

# Test
pytest tests/
pytest tests/test_app.py::TestAuthService::test_register_success  # single test
pytest --cov=app --cov-report=term-missing  # with coverage

# Lint
flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
```

### Frontend

```bash
cd frontend
npm install
npm start   # development server on :3000
npm test    # run tests
npm build   # production build
```

### Kubernetes/OpenShift Manifests

```bash
# Preview Kustomize output for an environment
kubectl kustomize manifests_v2/overlays/dev/
kubectl kustomize manifests_v2/overlays/staging/
kubectl kustomize manifests_v2/overlays/prod/

# Apply directly (without ArgoCD)
kubectl apply -k manifests_v2/overlays/dev/

# Diff against cluster
kubectl diff -k manifests_v2/overlays/dev/
```

### Sealed Secrets

```bash
cd manifests_v2/sealed-secrets
./seal-all-secrets.sh dev      # seal secrets for dev environment
./seal-all-secrets.sh staging
./seal-all-secrets.sh prod
```

## Code Architecture

### Directory Structure

- `auth-service/` - Flask authentication service (JWT, bcrypt, PostgreSQL)
- `game-service/` - Flask game logic service
- `frontend/` - React app with Tailwind CSS
- `manifests/` - Legacy Kubernetes manifests (simple deployments)
- `manifests_v2/` - Production Kustomize manifests with overlays

### manifests_v2/ Structure (GitOps)

```
manifests_v2/
├── base/                    # Shared network policies
├── auth-service/            # Base deployment, service, configmap
├── game-service/            # Base deployment, service, configmap
├── frontend/                # Base deployment, service, configmap, route
├── overlays/
│   ├── dev/                 # 1 replica, CNPG 1 instance, auto-sync
│   ├── staging/             # 2 replicas, CNPG 2 instances, manual sync
│   └── prod/                # 3 replicas, CNPG 3 instances HA, HPA, manual sync
├── argocd/                  # ArgoCD Application definitions
└── sealed-secrets/          # Sealed secrets tooling
```

### CI/CD Pipeline

GitHub Actions workflows in `.github/workflows/`:

1. **Push to master** → Build image `:staging-{sha}` + `:dev` → Auto-deploy to dev
2. **After build** → Security scan → Tag `:staging` → Manual sync to staging
3. **Git tag `service/vX.X.X`** → Tag `:vX.X.X` + `:latest` → Manual sync to prod

Production release tags follow the pattern: `auth/v1.0.0`, `game/v1.0.0`, `frontend/v1.0.0`

### Database

CloudNativePG (CNPG) manages PostgreSQL. Secrets are auto-generated:
- `postgres-{env}-app` - Application credentials (used by deployments)
- `postgres-{env}-superuser` - Admin credentials

### Key Configuration Notes

- Services require these env vars: `POSTGRES_HOST`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- Auth service JWT secret is hardcoded as `"your-secret-key"` in `auth-service/app.py:16`
- All Python services expose Prometheus metrics at `/metrics`
- Frontend proxies API calls via nginx in production

### OpenShift Specifics

- Containers run with `readOnlyRootFilesystem: true` - deployments include emptyDir for `/tmp`
- CNPG pods require `inheritedLabels` for network policies to work
- Kustomize overlays use `includeSelectors: false` to avoid label selector conflicts
