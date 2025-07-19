#!/bin/bash

# Deploy ConfigMaps Script for League Simulator Team Data
# This script deploys all team data ConfigMaps to the Kubernetes cluster

set -e

NAMESPACE="league-simulator"
CONFIGMAP_DIR="k8s/configmaps"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== League Simulator ConfigMap Deployment ==="
echo "Project root: $PROJECT_ROOT"
echo "ConfigMap directory: $CONFIGMAP_DIR"
echo "Target namespace: $NAMESPACE"
echo

cd "$PROJECT_ROOT"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl and ensure it's in your PATH."
    exit 1
fi

# Check if we can access the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot access Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

echo "✓ kubectl available and cluster accessible"

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
else
    echo "✓ Namespace $NAMESPACE already exists"
fi

# Check if ConfigMap directory exists
if [ ! -d "$CONFIGMAP_DIR" ]; then
    echo "❌ ConfigMap directory not found: $CONFIGMAP_DIR"
    echo "Please run the ConfigMap generator first:"
    echo "  Rscript k8s/templates/configmap-generator.R"
    exit 1
fi

# Find all ConfigMap YAML files
CONFIGMAP_FILES=($(find "$CONFIGMAP_DIR" -name "team-data-*.yaml" | sort))

if [ ${#CONFIGMAP_FILES[@]} -eq 0 ]; then
    echo "❌ No ConfigMap YAML files found in $CONFIGMAP_DIR"
    echo "Please run the ConfigMap generator first:"
    echo "  Rscript k8s/templates/configmap-generator.R"
    exit 1
fi

echo "Found ${#CONFIGMAP_FILES[@]} ConfigMap files:"
for file in "${CONFIGMAP_FILES[@]}"; do
    echo "  - $(basename "$file")"
done
echo

# Deploy each ConfigMap
SUCCESS_COUNT=0
FAILED_COUNT=0

for configmap_file in "${CONFIGMAP_FILES[@]}"; do
    configmap_name=$(basename "$configmap_file" .yaml)
    echo "Deploying $configmap_name..."
    
    if kubectl apply -f "$configmap_file" -n "$NAMESPACE"; then
        echo "✓ Successfully deployed $configmap_name"
        ((SUCCESS_COUNT++))
    else
        echo "❌ Failed to deploy $configmap_name"
        ((FAILED_COUNT++))
    fi
    echo
done

# Summary
echo "=== Deployment Summary ==="
echo "✓ Successful deployments: $SUCCESS_COUNT"
echo "❌ Failed deployments: $FAILED_COUNT"
echo

if [ $FAILED_COUNT -eq 0 ]; then
    echo "🎉 All ConfigMaps deployed successfully!"
    
    # Verify deployments
    echo
    echo "=== Verification ==="
    echo "ConfigMaps in namespace $NAMESPACE:"
    kubectl get configmaps -n "$NAMESPACE" | grep "team-data-"
    
    echo
    echo "Next steps:"
    echo "1. Deploy the updated application deployments:"
    echo "   kubectl apply -f k8s/k8s-deployment.yaml"
    echo "2. Verify pods start successfully:"
    echo "   kubectl get pods -n $NAMESPACE"
    echo "3. Check ConfigMap mounts:"
    echo "   kubectl exec -n $NAMESPACE deployment/league-updater-bl -- ls -la /RCode/TeamList_*.csv"
    
else
    echo "⚠️  Some ConfigMaps failed to deploy. Please check the errors above."
    exit 1
fi