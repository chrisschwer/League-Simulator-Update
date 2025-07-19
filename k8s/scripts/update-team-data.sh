#!/bin/bash

# Update Team Data Script for League Simulator
# This script updates team data ConfigMaps and triggers pod restarts

set -e

NAMESPACE="league-simulator"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Function to show usage
show_usage() {
    echo "Usage: $0 <season> <csv_file> [options]"
    echo ""
    echo "Arguments:"
    echo "  season     Season year (e.g., 2025)"
    echo "  csv_file   Path to updated TeamList CSV file"
    echo ""
    echo "Options:"
    echo "  --dry-run     Show what would be done without making changes"
    echo "  --no-restart  Don't restart pods after updating ConfigMap"
    echo "  --version     ConfigMap version (default: auto-increment)"
    echo "  --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 2025 RCode/TeamList_2025.csv"
    echo "  $0 2024 /path/to/updated/TeamList_2024.csv --dry-run"
    echo "  $0 2025 TeamList_2025.csv --version 1.1.0 --no-restart"
}

# Parse command line arguments
SEASON=""
CSV_FILE=""
DRY_RUN=false
NO_RESTART=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-restart)
            NO_RESTART=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$SEASON" ]; then
                SEASON="$1"
            elif [ -z "$CSV_FILE" ]; then
                CSV_FILE="$1"
            else
                echo "Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$SEASON" ] || [ -z "$CSV_FILE" ]; then
    echo "❌ Missing required arguments"
    show_usage
    exit 1
fi

# Validate season format
if [[ ! "$SEASON" =~ ^[0-9]{4}$ ]]; then
    echo "❌ Invalid season format. Expected 4-digit year (e.g., 2025)"
    exit 1
fi

echo "=== League Simulator Team Data Update ==="
echo "Season: $SEASON"
echo "CSV file: $CSV_FILE"
echo "Namespace: $NAMESPACE"
echo "Dry run: $DRY_RUN"
echo

cd "$PROJECT_ROOT"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl and ensure it's in your PATH."
    exit 1
fi

# Check if CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    echo "❌ CSV file not found: $CSV_FILE"
    exit 1
fi

# Validate CSV file format
echo "Validating CSV file format..."
if ! head -1 "$CSV_FILE" | grep -q "TeamID;ShortText;Promotion;InitialELO"; then
    echo "❌ Invalid CSV format. Expected header: TeamID;ShortText;Promotion;InitialELO"
    exit 1
fi

TEAM_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l | tr -d ' ')
echo "✓ CSV file valid. Found $TEAM_COUNT teams"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ Namespace $NAMESPACE not found. Please create it first."
    exit 1
fi

# Get current ConfigMap version
CONFIGMAP_NAME="team-data-$SEASON"
CURRENT_VERSION=""

if kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" &> /dev/null; then
    CURRENT_VERSION=$(kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.version}' 2>/dev/null || echo "")
    echo "Current ConfigMap version: ${CURRENT_VERSION:-"unknown"}"
else
    echo "ConfigMap $CONFIGMAP_NAME does not exist yet"
fi

# Determine new version
if [ -z "$VERSION" ]; then
    if [ -n "$CURRENT_VERSION" ]; then
        # Auto-increment patch version
        if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
            MAJOR="${BASH_REMATCH[1]}"
            MINOR="${BASH_REMATCH[2]}"
            PATCH="${BASH_REMATCH[3]}"
            NEW_PATCH=$((PATCH + 1))
            VERSION="$MAJOR.$MINOR.$NEW_PATCH"
        else
            VERSION="1.0.1"
        fi
    else
        VERSION="1.0.0"
    fi
fi

echo "New ConfigMap version: $VERSION"

if [ "$DRY_RUN" = true ]; then
    echo
    echo "=== DRY RUN - No changes will be made ==="
    echo "Would perform the following actions:"
    echo "1. Generate new ConfigMap YAML for season $SEASON"
    echo "2. Update ConfigMap $CONFIGMAP_NAME to version $VERSION"
    echo "3. Include $TEAM_COUNT teams from $CSV_FILE"
    if [ "$NO_RESTART" = false ]; then
        echo "4. Restart deployments: league-updater-bl, league-updater-bl2, league-updater-liga3, shiny-updater"
    fi
    exit 0
fi

# Generate new ConfigMap YAML
echo
echo "Generating new ConfigMap YAML..."
TEMP_CSV=$(mktemp)
cp "$CSV_FILE" "$TEMP_CSV"

# Use R script to generate ConfigMap YAML
if ! Rscript -e "
source('k8s/templates/configmap-generator.R')
yaml_file <- generate_configmap_yaml('$TEMP_CSV', '$SEASON', '$VERSION')
cat('Generated:', yaml_file, '\n')
" 2>/dev/null; then
    echo "❌ Failed to generate ConfigMap YAML"
    rm -f "$TEMP_CSV"
    exit 1
fi

rm -f "$TEMP_CSV"

# Apply the updated ConfigMap
CONFIGMAP_FILE="k8s/configmaps/$CONFIGMAP_NAME.yaml"
echo "Applying ConfigMap update..."

if kubectl apply -f "$CONFIGMAP_FILE" -n "$NAMESPACE"; then
    echo "✓ ConfigMap $CONFIGMAP_NAME updated successfully"
else
    echo "❌ Failed to update ConfigMap"
    exit 1
fi

# Restart deployments if requested
if [ "$NO_RESTART" = false ]; then
    echo
    echo "Triggering rolling restart of deployments..."
    
    DEPLOYMENTS=("league-updater-bl" "league-updater-bl2" "league-updater-liga3" "shiny-updater")
    
    for deployment in "${DEPLOYMENTS[@]}"; do
        echo "Restarting $deployment..."
        if kubectl rollout restart deployment "$deployment" -n "$NAMESPACE"; then
            echo "✓ Triggered restart for $deployment"
        else
            echo "⚠️  Failed to restart $deployment (may not exist)"
        fi
    done
    
    echo
    echo "Waiting for rollout to complete..."
    for deployment in "${DEPLOYMENTS[@]}"; do
        if kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
            echo "Waiting for $deployment..."
            kubectl rollout status deployment "$deployment" -n "$NAMESPACE" --timeout=300s || true
        fi
    done
fi

echo
echo "=== Update Summary ==="
echo "✓ ConfigMap $CONFIGMAP_NAME updated to version $VERSION"
echo "✓ Team count: $TEAM_COUNT"
echo "✓ Source file: $CSV_FILE"

if [ "$NO_RESTART" = false ]; then
    echo "✓ Deployments restarted"
    echo
    echo "Verification commands:"
    echo "  kubectl get configmaps -n $NAMESPACE | grep team-data"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl exec -n $NAMESPACE deployment/league-updater-bl -- head -5 /RCode/TeamList_$SEASON.csv"
else
    echo "⚠️  Pods not restarted (--no-restart flag used)"
    echo "   Manual restart required for changes to take effect"
fi

echo
echo "🎉 Team data update completed successfully!"