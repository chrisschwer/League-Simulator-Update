#!/bin/bash

# Status checking script for League Simulator deployment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}$1${NC}"
    printf '=%.0s' {1..50}
    echo ""
}

print_status() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# Check if namespace exists
if ! kubectl get namespace league-simulator &> /dev/null; then
    print_error "League Simulator namespace not found. Is it deployed?"
    exit 1
fi

echo "🏆 League Simulator Status Dashboard"
echo "===================================="
echo ""

# Namespace status
print_header "📊 Namespace Information"
kubectl describe namespace league-simulator | grep -E "Name:|Phase:|Age:"
echo ""

# Pod status
print_header "🚀 Pod Status"
echo ""
kubectl -n league-simulator get pods -o wide
echo ""

# Check if pods are running
RUNNING_PODS=$(kubectl -n league-simulator get pods --field-selector=status.phase=Running --no-headers | wc -l)
TOTAL_PODS=$(kubectl -n league-simulator get pods --no-headers | wc -l)

if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
    print_status "All $TOTAL_PODS pods are running"
else
    print_warning "$RUNNING_PODS out of $TOTAL_PODS pods are running"
fi
echo ""

# Deployment status
print_header "📋 Deployment Status"
echo ""
kubectl -n league-simulator get deployments -o wide
echo ""

# Service status
print_header "🌐 Service Status"
echo ""
if kubectl -n league-simulator get services --no-headers | grep -q .; then
    kubectl -n league-simulator get services -o wide
else
    echo "No services found"
fi
echo ""

# Storage status
print_header "💾 Storage Status"
echo ""
kubectl -n league-simulator get pvc -o wide
echo ""

# ConfigMap status
print_header "🔧 Configuration"
echo ""
if kubectl -n league-simulator get configmap league-simulator-config &> /dev/null; then
    echo "ConfigMap contents:"
    kubectl -n league-simulator get configmap league-simulator-config -o yaml | grep -A 20 "data:"
else
    print_warning "ConfigMap not found"
fi
echo ""

# Secret status (without revealing content)
print_header "🔐 Secrets Status"
echo ""
if kubectl -n league-simulator get secret league-simulator-secrets &> /dev/null; then
    kubectl -n league-simulator get secret league-simulator-secrets -o wide
    echo ""
    echo "Secret keys:"
    kubectl -n league-simulator get secret league-simulator-secrets -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "Keys: RAPIDAPI_KEY, SHINYAPPS_IO_SECRET"
else
    print_warning "Secrets not found"
fi
echo ""

# Recent events
print_header "📝 Recent Events"
echo ""
kubectl -n league-simulator get events --sort-by='.lastTimestamp' | tail -10
echo ""

# Resource usage
print_header "📈 Resource Usage"
echo ""
if kubectl top pods -n league-simulator &> /dev/null; then
    kubectl top pods -n league-simulator
else
    print_warning "Metrics server not available - resource usage unavailable"
fi
echo ""

# Health check summary
print_header "🏥 Health Summary"
echo ""

# Check deployment readiness
READY_DEPLOYMENTS=$(kubectl -n league-simulator get deployments --no-headers | awk '$2==$4 {count++} END {print count+0}')
TOTAL_DEPLOYMENTS=$(kubectl -n league-simulator get deployments --no-headers | wc -l)

if [ "$READY_DEPLOYMENTS" -eq "$TOTAL_DEPLOYMENTS" ] && [ "$TOTAL_DEPLOYMENTS" -gt 0 ]; then
    print_status "All deployments are ready ($READY_DEPLOYMENTS/$TOTAL_DEPLOYMENTS)"
else
    print_warning "Only $READY_DEPLOYMENTS out of $TOTAL_DEPLOYMENTS deployments are ready"
fi

# Check PVC status
PVC_BOUND=$(kubectl -n league-simulator get pvc --no-headers | grep -c "Bound" || echo "0")
TOTAL_PVC=$(kubectl -n league-simulator get pvc --no-headers | wc -l)

if [ "$PVC_BOUND" -eq "$TOTAL_PVC" ] && [ "$TOTAL_PVC" -gt 0 ]; then
    print_status "All persistent volumes are bound ($PVC_BOUND/$TOTAL_PVC)"
elif [ "$TOTAL_PVC" -gt 0 ]; then
    print_warning "Only $PVC_BOUND out of $TOTAL_PVC persistent volumes are bound"
fi

echo ""
echo "🔍 Quick Commands:"
echo "- Watch pods: kubectl -n league-simulator get pods -w"
echo "- View logs: kubectl -n league-simulator logs -l app=league-updater -f"
echo "- Port forward Shiny: kubectl -n league-simulator port-forward deployment/shiny-updater 3838:3838"
echo "- Scale deployment: kubectl -n league-simulator scale deployment league-updater-bl --replicas=2"
echo ""