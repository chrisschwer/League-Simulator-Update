#!/bin/bash

# ConfigMap Operations Script for League Simulator
# This script provides various operations for managing team data ConfigMaps

set -e

NAMESPACE="league-simulator"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Function to show usage
show_usage() {
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  list                          List all team data ConfigMaps"
    echo "  show <season>                 Show details of a specific ConfigMap"
    echo "  update <season> <csv_file>    Update team data for a season"
    echo "  rollback <season> <version>   Rollback to a previous version"
    echo "  verify [season]               Verify ConfigMap deployments"
    echo "  backup <season>               Backup current ConfigMap"
    echo "  diff <season> <csv_file>      Compare current data with new CSV"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 show 2025"
    echo "  $0 update 2025 RCode/TeamList_2025.csv"
    echo "  $0 rollback 2025 1.0.0"
    echo "  $0 verify"
    echo "  $0 backup 2025"
    echo "  $0 diff 2025 new_team_data.csv"
}

# Function to list ConfigMaps
list_configmaps() {
    echo "=== Team Data ConfigMaps in namespace: $NAMESPACE ==="
    echo
    
    if ! kubectl get configmaps -n "$NAMESPACE" | grep -q "team-data-"; then
        echo "No team data ConfigMaps found."
        return
    fi
    
    echo "NAME                    SEASON  VERSION  TEAMS  AGE"
    echo "----                    ------  -------  -----  ---"
    
    kubectl get configmaps -n "$NAMESPACE" -o json | jq -r '
        .items[] | 
        select(.metadata.name | startswith("team-data-")) |
        "\(.metadata.name)   \(.metadata.labels.season // "unknown")       \(.metadata.labels.version // "unknown")      \(.metadata.annotations."team-count" // "unknown")     \(.metadata.creationTimestamp)"
    ' | while read line; do
        if [ -n "$line" ]; then
            name=$(echo "$line" | awk '{print $1}')
            season=$(echo "$line" | awk '{print $2}')
            version=$(echo "$line" | awk '{print $3}')
            teams=$(echo "$line" | awk '{print $4}')
            timestamp=$(echo "$line" | awk '{print $5}')
            
            # Calculate age
            if command -v gdate &> /dev/null; then
                # macOS with GNU date
                age=$(gdate -d "$timestamp" +%s)
                now=$(gdate +%s)
            else
                # Linux date
                age=$(date -d "$timestamp" +%s)
                now=$(date +%s)
            fi
            
            age_diff=$((now - age))
            age_human=""
            
            if [ $age_diff -lt 3600 ]; then
                age_human="${age_diff}s"
            elif [ $age_diff -lt 86400 ]; then
                age_human="$((age_diff / 3600))h"
            else
                age_human="$((age_diff / 86400))d"
            fi
            
            printf "%-23s %-7s %-8s %-6s %s\n" "$name" "$season" "$version" "$teams" "$age_human"
        fi
    done
}

# Function to show ConfigMap details
show_configmap() {
    local season="$1"
    if [ -z "$season" ]; then
        echo "❌ Season required for show command"
        exit 1
    fi
    
    local configmap_name="team-data-$season"
    
    if ! kubectl get configmap "$configmap_name" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ ConfigMap $configmap_name not found in namespace $NAMESPACE"
        exit 1
    fi
    
    echo "=== ConfigMap Details: $configmap_name ==="
    echo
    
    # Show metadata
    echo "Metadata:"
    kubectl get configmap "$configmap_name" -n "$NAMESPACE" -o jsonpath='{.metadata}' | jq '
        {
            name: .name,
            namespace: .namespace,
            labels: .labels,
            annotations: .annotations,
            creationTimestamp: .creationTimestamp
        }
    '
    
    echo
    echo "Team Data Preview (first 10 teams):"
    kubectl get configmap "$configmap_name" -n "$NAMESPACE" -o jsonpath="{.data.TeamList_${season}\.csv}" | head -11
    
    echo
    echo "Statistics:"
    local team_count=$(kubectl get configmap "$configmap_name" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.team-count}')
    local version=$(kubectl get configmap "$configmap_name" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.version}')
    local source_file=$(kubectl get configmap "$configmap_name" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.source-file}')
    
    echo "  Teams: $team_count"
    echo "  Version: $version"
    echo "  Source: $source_file"
}

# Function to verify ConfigMap deployments
verify_configmaps() {
    local season="$1"
    echo "=== Verifying ConfigMap Deployments ==="
    echo
    
    # Check if deployments are running
    local deployments=("league-updater-bl" "league-updater-bl2" "league-updater-liga3" "shiny-updater")
    
    for deployment in "${deployments[@]}"; do
        echo "Checking $deployment..."
        
        if ! kubectl get deployment "$deployment" -n "$NAMESPACE" &> /dev/null; then
            echo "  ⚠️  Deployment not found"
            continue
        fi
        
        local ready_replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
        
        if [ "$ready_replicas" = "$desired_replicas" ]; then
            echo "  ✓ Running ($ready_replicas/$desired_replicas replicas)"
            
            # Check ConfigMap mounts
            local pod_name=$(kubectl get pods -n "$NAMESPACE" -l app=league-updater -l deployment="$deployment" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            
            if [ -n "$pod_name" ]; then
                echo "  Checking ConfigMap mounts in pod: $pod_name"
                
                if [ -n "$season" ]; then
                    # Check specific season
                    if kubectl exec -n "$NAMESPACE" "$pod_name" -- test -f "/RCode/TeamList_${season}.csv" 2>/dev/null; then
                        local team_count=$(kubectl exec -n "$NAMESPACE" "$pod_name" -- wc -l < "/RCode/TeamList_${season}.csv" 2>/dev/null || echo "unknown")
                        echo "    ✓ TeamList_${season}.csv mounted ($team_count lines)"
                    else
                        echo "    ❌ TeamList_${season}.csv not found"
                    fi
                else
                    # Check all seasons
                    kubectl exec -n "$NAMESPACE" "$pod_name" -- ls -la /RCode/TeamList_*.csv 2>/dev/null | while read line; do
                        if [[ "$line" =~ TeamList_([0-9]{4})\.csv ]]; then
                            echo "    ✓ $line"
                        fi
                    done || echo "    ❌ No TeamList files found"
                fi
            fi
        else
            echo "  ❌ Not ready ($ready_replicas/$desired_replicas replicas)"
        fi
        echo
    done
}

# Function to backup ConfigMap
backup_configmap() {
    local season="$1"
    if [ -z "$season" ]; then
        echo "❌ Season required for backup command"
        exit 1
    fi
    
    local configmap_name="team-data-$season"
    local backup_dir="backups/configmaps"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/${configmap_name}_${timestamp}.yaml"
    
    mkdir -p "$backup_dir"
    
    if ! kubectl get configmap "$configmap_name" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ ConfigMap $configmap_name not found"
        exit 1
    fi
    
    echo "Creating backup of $configmap_name..."
    kubectl get configmap "$configmap_name" -n "$NAMESPACE" -o yaml > "$backup_file"
    
    echo "✓ Backup created: $backup_file"
    echo "  Size: $(du -h "$backup_file" | awk '{print $1}')"
    
    # Show recent backups
    echo
    echo "Recent backups for season $season:"
    ls -lt "$backup_dir" | grep "$configmap_name" | head -5
}

# Function to diff ConfigMap with new CSV
diff_configmap() {
    local season="$1"
    local csv_file="$2"
    
    if [ -z "$season" ] || [ -z "$csv_file" ]; then
        echo "❌ Both season and CSV file required for diff command"
        exit 1
    fi
    
    if [ ! -f "$csv_file" ]; then
        echo "❌ CSV file not found: $csv_file"
        exit 1
    fi
    
    local configmap_name="team-data-$season"
    
    if ! kubectl get configmap "$configmap_name" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ ConfigMap $configmap_name not found"
        exit 1
    fi
    
    echo "=== Comparing ConfigMap with new CSV ==="
    echo "ConfigMap: $configmap_name"
    echo "CSV file: $csv_file"
    echo
    
    # Extract current CSV from ConfigMap
    local temp_current=$(mktemp)
    kubectl get configmap "$configmap_name" -n "$NAMESPACE" -o jsonpath="{.data.TeamList_${season}\.csv}" > "$temp_current"
    
    # Show line count comparison
    local current_lines=$(wc -l < "$temp_current")
    local new_lines=$(wc -l < "$csv_file")
    
    echo "Line count:"
    echo "  Current: $current_lines"
    echo "  New:     $new_lines"
    echo "  Diff:    $((new_lines - current_lines))"
    echo
    
    # Show actual diff
    echo "Differences (current vs new):"
    if diff -u "$temp_current" "$csv_file" | head -50; then
        echo "No differences found"
    fi
    
    rm -f "$temp_current"
}

# Main command dispatch
COMMAND="$1"
shift 2>/dev/null || true

cd "$PROJECT_ROOT"

# Check dependencies
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found. Please install jq for JSON processing."
    exit 1
fi

case "$COMMAND" in
    list)
        list_configmaps
        ;;
    show)
        show_configmap "$1"
        ;;
    update)
        exec "$SCRIPT_DIR/update-team-data.sh" "$@"
        ;;
    rollback)
        echo "⚠️  Rollback functionality not yet implemented"
        echo "Manual rollback steps:"
        echo "1. Apply previous ConfigMap YAML from backup"
        echo "2. Restart deployments"
        exit 1
        ;;
    verify)
        verify_configmaps "$1"
        ;;
    backup)
        backup_configmap "$1"
        ;;
    diff)
        diff_configmap "$1" "$2"
        ;;
    ""|--help|-h|help)
        show_usage
        ;;
    *)
        echo "❌ Unknown command: $COMMAND"
        echo
        show_usage
        exit 1
        ;;
esac