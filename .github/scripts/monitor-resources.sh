#!/bin/bash
# Monitor resource usage during test execution

# Output file for metrics
METRICS_FILE="${METRICS_FILE:-resource-metrics.json}"
INTERVAL="${MONITORING_INTERVAL:-5}"

# Initialize metrics
echo '{"measurements": []}' > "$METRICS_FILE"

# Function to get current metrics
get_metrics() {
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # CPU usage
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        cpu_usage=$(ps -A -o %cpu | awk '{s+=$1} END {print s}')
    else
        # Linux
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    fi
    
    # Memory usage
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        mem_info=$(vm_stat | grep -E "Pages (free|active|inactive|speculative|wired down)")
        page_size=$(vm_stat | grep "page size" | awk '{print $8}')
        pages_free=$(echo "$mem_info" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        pages_active=$(echo "$mem_info" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        pages_inactive=$(echo "$mem_info" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        pages_wired=$(echo "$mem_info" | grep "Pages wired" | awk '{print $4}' | sed 's/\.//')
        
        total_pages=$((pages_free + pages_active + pages_inactive + pages_wired))
        used_pages=$((pages_active + pages_wired))
        mem_usage_pct=$((used_pages * 100 / total_pages))
        mem_usage_mb=$((used_pages * page_size / 1048576))
    else
        # Linux
        mem_info=$(free -m | grep "Mem:")
        total_mem=$(echo $mem_info | awk '{print $2}')
        used_mem=$(echo $mem_info | awk '{print $3}')
        mem_usage_pct=$((used_mem * 100 / total_mem))
        mem_usage_mb=$used_mem
    fi
    
    # Disk I/O (simplified)
    if command -v iostat &> /dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            disk_io=$(iostat -d 1 2 | tail -1 | awk '{print $3}')
        else
            disk_io=$(iostat -d 1 2 | grep -A1 "Device" | tail -1 | awk '{print $2}')
        fi
    else
        disk_io="0"
    fi
    
    # Create JSON entry
    cat <<EOF
{
    "timestamp": "$timestamp",
    "cpu_usage_pct": $cpu_usage,
    "memory_usage_pct": $mem_usage_pct,
    "memory_usage_mb": $mem_usage_mb,
    "disk_io_kbs": $disk_io
}
EOF
}

# Function to append metrics to file
append_metrics() {
    metric=$1
    
    # Use jq if available, otherwise use awk
    if command -v jq &> /dev/null; then
        jq ".measurements += [$metric]" "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    else
        # Simple append using awk
        awk -v new="$metric" '
            /^{/ && !printed {print "{\"measurements\": ["; printed=1}
            /"measurements": \[/ {next}
            /^\]/ {if(NR>2) print ","; print new; print "]}"} 
            /^}/ {next}
            {if(NR>2 && printed) print}
        ' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    fi
}

# Function to generate summary
generate_summary() {
    if command -v jq &> /dev/null; then
        summary=$(jq -r '
            .measurements | 
            {
                max_cpu: (map(.cpu_usage_pct) | max),
                avg_cpu: (map(.cpu_usage_pct) | add / length),
                max_memory_mb: (map(.memory_usage_mb) | max),
                avg_memory_mb: (map(.memory_usage_mb) | add / length),
                max_memory_pct: (map(.memory_usage_pct) | max),
                samples: length
            }
        ' "$METRICS_FILE")
        
        echo "## Resource Usage Summary"
        echo "$summary" | jq -r '
            "- Maximum CPU Usage: \(.max_cpu | tostring | .[0:5])%",
            "- Average CPU Usage: \(.avg_cpu | tostring | .[0:5])%",
            "- Maximum Memory: \(.max_memory_mb)MB (\(.max_memory_pct)%)",
            "- Average Memory: \(.avg_memory_mb | tostring | .[0:6])MB",
            "- Samples Collected: \(.samples)"
        '
    else
        echo "## Resource Usage Summary"
        echo "Summary generation requires jq to be installed"
    fi
}

# Main monitoring loop
echo "Starting resource monitoring (interval: ${INTERVAL}s)..."

# Trap to ensure we generate summary on exit
trap 'generate_summary; exit' INT TERM EXIT

while true; do
    metric=$(get_metrics)
    append_metrics "$metric"
    
    # Also output to console if verbose
    if [[ "${VERBOSE}" == "true" ]]; then
        echo "$(date): CPU: $(echo "$metric" | grep cpu_usage_pct | awk -F: '{print $2}' | tr -d ' ,')% | Memory: $(echo "$metric" | grep memory_usage_mb | awk -F: '{print $2}' | tr -d ' ,')MB"
    fi
    
    sleep "$INTERVAL"
done