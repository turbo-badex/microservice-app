#!/bin/bash
#
# seal-all-secrets.sh
#
# This script seals all secrets for a given environment.
# Run this locally - NEVER in CI/CD pipelines.
#
# Usage:
#   ./seal-all-secrets.sh dev
#   ./seal-all-secrets.sh staging
#   ./seal-all-secrets.sh prod
#

set -e

# Configuration
ENVIRONMENT="${1:-dev}"
CERT_FILE="pub-sealed-secrets.pem"
MANIFESTS_DIR="$(dirname "$0")/.."

case $ENVIRONMENT in
    dev)
        NAMESPACE="microservice-app-dev"
        OVERLAY_DIR="${MANIFESTS_DIR}/overlays/dev"
        ;;
    staging)
        NAMESPACE="microservice-app-staging"
        OVERLAY_DIR="${MANIFESTS_DIR}/overlays/staging"
        ;;
    prod)
        NAMESPACE="microservice-app-prod"
        OVERLAY_DIR="${MANIFESTS_DIR}/overlays/prod"
        ;;
    *)
        echo "Usage: $0 [dev|staging|prod]"
        exit 1
        ;;
esac

echo "=============================================="
echo "Sealing secrets for: $ENVIRONMENT"
echo "Namespace: $NAMESPACE"
echo "Output directory: $OVERLAY_DIR"
echo "=============================================="
echo ""

# Check for kubeseal
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed"
    echo "Install with: brew install kubeseal (macOS)"
    exit 1
fi

# Check for oc/kubectl
if command -v oc &> /dev/null; then
    KUBECTL="oc"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
else
    echo "Error: neither oc nor kubectl found"
    exit 1
fi

# Fetch certificate if not exists
if [ ! -f "$CERT_FILE" ]; then
    echo "Fetching Sealed Secrets certificate..."
    kubeseal --fetch-cert \
        --controller-name=sealed-secrets-controller \
        --controller-namespace=kube-system \
        > "$CERT_FILE"
    echo "Certificate saved to: $CERT_FILE"
fi

echo ""
echo "=== Docker Hub Credentials ==="
echo "Enter Docker Hub username:"
read DOCKER_USER
echo "Enter Docker Hub password (input hidden):"
read -s DOCKER_PASS
echo ""
echo "Enter Docker Hub email:"
read DOCKER_EMAIL

echo ""
echo "Creating sealed Docker registry secret..."

$KUBECTL create secret docker-registry dockerhub-cred \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="$DOCKER_USER" \
    --docker-password="$DOCKER_PASS" \
    --docker-email="$DOCKER_EMAIL" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | \
kubeseal --format=yaml --cert="$CERT_FILE" \
    > "${OVERLAY_DIR}/sealed-dockerhub-secret.yaml"

echo "Created: ${OVERLAY_DIR}/sealed-dockerhub-secret.yaml"

echo ""
echo "=== JWT Secret ==="
echo "Generate new JWT secret? (y/n)"
read GENERATE_JWT

if [ "$GENERATE_JWT" = "y" ]; then
    JWT_SECRET=$(openssl rand -base64 32)
    echo ""
    echo "========================================="
    echo "IMPORTANT: Save this JWT secret securely!"
    echo "JWT_SECRET_KEY: $JWT_SECRET"
    echo "========================================="
    echo ""
else
    echo "Enter existing JWT secret:"
    read -s JWT_SECRET
    echo ""
fi

echo "Creating sealed auth-service secret..."
cat <<EOF | kubeseal --format=yaml --cert="$CERT_FILE" > "${OVERLAY_DIR}/sealed-auth-service-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: auth-service-secret
  namespace: $NAMESPACE
  labels:
    app: auth-service
    app.kubernetes.io/name: auth-service
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: microservice-app
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
type: Opaque
stringData:
  JWT_SECRET_KEY: "$JWT_SECRET"
EOF

echo "Created: ${OVERLAY_DIR}/sealed-auth-service-secret.yaml"

echo "Creating sealed game-service secret..."
cat <<EOF | kubeseal --format=yaml --cert="$CERT_FILE" > "${OVERLAY_DIR}/sealed-game-service-secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: game-service-secret
  namespace: $NAMESPACE
  labels:
    app: game-service
    app.kubernetes.io/name: game-service
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: microservice-app
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
type: Opaque
stringData:
  JWT_SECRET_KEY: "$JWT_SECRET"
EOF

echo "Created: ${OVERLAY_DIR}/sealed-game-service-secret.yaml"

echo ""
echo "=============================================="
echo "Done! Sealed secrets created:"
echo "  - ${OVERLAY_DIR}/sealed-dockerhub-secret.yaml"
echo "  - ${OVERLAY_DIR}/sealed-auth-service-secret.yaml"
echo "  - ${OVERLAY_DIR}/sealed-game-service-secret.yaml"
echo ""
echo "Next steps:"
echo "1. Update ${OVERLAY_DIR}/kustomization.yaml to include sealed secrets"
echo "2. Remove or comment out the plain secret references"
echo "3. Commit the sealed secrets to Git"
echo "=============================================="
