# Sealed Secrets Setup Guide

This guide explains how to use Bitnami Sealed Secrets to securely store secrets in Git for GitOps workflows.

## What is Sealed Secrets?

Sealed Secrets is a Kubernetes controller that allows you to encrypt secrets so they can be safely stored in Git. Only the controller running in your cluster can decrypt them.

```
┌─────────────────────────────────────────────────────────────────┐
│                     Sealed Secrets Flow                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   LOCAL                        CLUSTER                         │
│   ┌──────────────┐            ┌──────────────┐                 │
│   │ Secret       │  kubeseal  │ SealedSecret │                 │
│   │ (plaintext)  │ ────────►  │ (encrypted)  │                 │
│   └──────────────┘            └──────┬───────┘                 │
│                                      │                         │
│                                      ▼                         │
│                               ┌──────────────┐                 │
│   ┌──────────────┐            │ Sealed       │                 │
│   │ Git Repo     │ ◄───────── │ Secrets      │                 │
│   │ (safe!)      │            │ Controller   │                 │
│   └──────────────┘            └──────┬───────┘                 │
│                                      │                         │
│                                      ▼                         │
│                               ┌──────────────┐                 │
│                               │ Secret       │                 │
│                               │ (decrypted)  │                 │
│                               └──────────────┘                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Step 1: Install Sealed Secrets Controller

### Option A: Via Helm (Recommended)

```bash
# Add the Sealed Secrets Helm repo
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# Install in the kube-system namespace
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set-string fullnameOverride=sealed-secrets-controller
```

### Option B: Via OperatorHub (OpenShift)

```
OpenShift Console → Operators → OperatorHub → Search "Sealed Secrets" → Install
```

### Verify Installation

```bash
# Check the controller is running
oc get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check the service
oc get svc -n kube-system sealed-secrets-controller
```

## Step 2: Install kubeseal CLI

### macOS

```bash
brew install kubeseal
```

### Linux

```bash
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | jq -r .tag_name | cut -c 2-)
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Verify

```bash
kubeseal --version
```

## Step 3: Fetch the Public Key

The public key is used to encrypt secrets locally. Only the controller has the private key to decrypt.

```bash
# Fetch and save the public key
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > pub-sealed-secrets.pem

# Keep this file - you'll need it to seal secrets
```

## Step 4: Create Sealed Secrets

### Docker Registry Secret (dockerhub-cred)

```bash
# 1. Create the secret YAML (don't apply it!)
oc create secret docker-registry dockerhub-cred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKER_USERNAME \
  --docker-password=YOUR_DOCKER_PASSWORD \
  --docker-email=YOUR_EMAIL \
  --namespace=microservice-app-dev \
  --dry-run=client -o yaml > dockerhub-secret.yaml

# 2. Seal the secret
kubeseal --format=yaml \
  --cert=pub-sealed-secrets.pem \
  < dockerhub-secret.yaml \
  > sealed-dockerhub-secret.yaml

# 3. Delete the plaintext secret (IMPORTANT!)
rm dockerhub-secret.yaml

# 4. View the sealed secret (safe to commit)
cat sealed-dockerhub-secret.yaml
```

### JWT Secret (auth-service-secret)

```bash
# 1. Generate a strong JWT secret
JWT_SECRET=$(openssl rand -base64 32)
echo "Generated JWT_SECRET: $JWT_SECRET"

# 2. Create the secret YAML
cat <<EOF > jwt-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth-service-secret
  namespace: microservice-app-dev
type: Opaque
stringData:
  JWT_SECRET_KEY: "${JWT_SECRET}"
EOF

# 3. Seal the secret
kubeseal --format=yaml \
  --cert=pub-sealed-secrets.pem \
  < jwt-secret.yaml \
  > sealed-jwt-secret.yaml

# 4. Delete the plaintext secret
rm jwt-secret.yaml

# 5. Repeat for game-service-secret with SAME JWT value
cat <<EOF > jwt-secret-game.yaml
apiVersion: v1
kind: Secret
metadata:
  name: game-service-secret
  namespace: microservice-app-dev
type: Opaque
stringData:
  JWT_SECRET_KEY: "${JWT_SECRET}"
EOF

kubeseal --format=yaml \
  --cert=pub-sealed-secrets.pem \
  < jwt-secret-game.yaml \
  > sealed-jwt-secret-game.yaml

rm jwt-secret-game.yaml
```

## Step 5: Replace Plain Secrets with Sealed Secrets

### Directory Structure After Sealing

```
manifests_v2/
├── sealed-secrets/
│   └── README.md
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── sealed-dockerhub-secret.yaml    # Sealed - safe for Git
│   │   ├── sealed-auth-service-secret.yaml # Sealed - safe for Git
│   │   └── sealed-game-service-secret.yaml # Sealed - safe for Git
│   ├── staging/
│   │   └── ... (same pattern)
│   └── prod/
│       └── ... (same pattern)
```

### Update Kustomization

In each overlay's `kustomization.yaml`, add the sealed secrets as resources:

```yaml
resources:
  - ../../
  - postgres-cluster.yaml
  - sealed-dockerhub-secret.yaml      # Add sealed secrets
  - sealed-auth-service-secret.yaml
  - sealed-game-service-secret.yaml
```

## Step 6: Sealing Secrets for Multiple Namespaces

Sealed Secrets are **namespace-scoped** by default. You need to seal secrets separately for each namespace:

```bash
# For dev
kubeseal --format=yaml --cert=pub-sealed-secrets.pem \
  --namespace=microservice-app-dev \
  < secret.yaml > overlays/dev/sealed-secret.yaml

# For staging
kubeseal --format=yaml --cert=pub-sealed-secrets.pem \
  --namespace=microservice-app-staging \
  < secret.yaml > overlays/staging/sealed-secret.yaml

# For prod
kubeseal --format=yaml --cert=pub-sealed-secrets.pem \
  --namespace=microservice-app-prod \
  < secret.yaml > overlays/prod/sealed-secret.yaml
```

## Complete Example Script

Here's a complete script to seal all secrets for an environment:

```bash
#!/bin/bash
# seal-secrets.sh - Run this locally, NOT in CI/CD

set -e

NAMESPACE="${1:-microservice-app-dev}"
OVERLAY_DIR="${2:-overlays/dev}"
CERT_FILE="pub-sealed-secrets.pem"

# Ensure we have the certificate
if [ ! -f "$CERT_FILE" ]; then
    echo "Fetching sealed secrets certificate..."
    kubeseal --fetch-cert \
        --controller-name=sealed-secrets-controller \
        --controller-namespace=kube-system \
        > "$CERT_FILE"
fi

# Docker registry secret
echo "Enter Docker Hub username:"
read DOCKER_USER
echo "Enter Docker Hub password:"
read -s DOCKER_PASS
echo "Enter Docker Hub email:"
read DOCKER_EMAIL

oc create secret docker-registry dockerhub-cred \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="$DOCKER_USER" \
    --docker-password="$DOCKER_PASS" \
    --docker-email="$DOCKER_EMAIL" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | \
kubeseal --format=yaml --cert="$CERT_FILE" \
    > "${OVERLAY_DIR}/sealed-dockerhub-secret.yaml"

echo "Created: ${OVERLAY_DIR}/sealed-dockerhub-secret.yaml"

# JWT secret (generate new or use existing)
JWT_SECRET=$(openssl rand -base64 32)
echo "Generated JWT_SECRET (save this!): $JWT_SECRET"

# Auth service secret
cat <<EOF | kubeseal --format=yaml --cert="$CERT_FILE" > "${OVERLAY_DIR}/sealed-auth-service-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: auth-service-secret
  namespace: $NAMESPACE
type: Opaque
stringData:
  JWT_SECRET_KEY: "$JWT_SECRET"
EOF

echo "Created: ${OVERLAY_DIR}/sealed-auth-service-secret.yaml"

# Game service secret (same JWT)
cat <<EOF | kubeseal --format=yaml --cert="$CERT_FILE" > "${OVERLAY_DIR}/sealed-game-service-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: game-service-secret
  namespace: $NAMESPACE
type: Opaque
stringData:
  JWT_SECRET_KEY: "$JWT_SECRET"
EOF

echo "Created: ${OVERLAY_DIR}/sealed-game-service-secret.yaml"

echo ""
echo "Done! Sealed secrets created in ${OVERLAY_DIR}/"
echo "You can now safely commit these files to Git."
```

## Troubleshooting

### Error: Cannot fetch certificate

```bash
# Check if controller is running
oc get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check controller logs
oc logs -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Error: Sealed secret not decrypting

```bash
# Check SealedSecret status
oc get sealedsecret -n microservice-app-dev

# Check for errors
oc describe sealedsecret auth-service-secret -n microservice-app-dev
```

### Error: Wrong namespace

Sealed secrets are bound to a namespace. If you see decryption errors, ensure:
1. The secret was sealed for the correct namespace
2. The namespace exists before applying

## Key Rotation

The Sealed Secrets controller rotates its keys periodically. Old sealed secrets remain valid.

To re-seal with new keys:

```bash
# Fetch new certificate
kubeseal --fetch-cert > pub-sealed-secrets-new.pem

# Re-seal all secrets with new certificate
# (follow the sealing steps again)
```

## Best Practices

1. **Never commit plaintext secrets** - Always delete after sealing
2. **Store the public key** - Keep `pub-sealed-secrets.pem` in your repo
3. **Backup the private key** - The cluster admin should backup the controller's private key
4. **Use strict namespace scope** - Don't use cluster-wide secrets unless necessary
5. **Rotate regularly** - Re-seal secrets when rotating credentials
6. **Seal per environment** - Each namespace needs its own sealed secrets
