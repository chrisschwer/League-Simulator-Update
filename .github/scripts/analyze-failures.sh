#!/bin/bash
# Automated test failure analysis

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to analyze error patterns
analyze_error_patterns() {
    local log_file="$1"
    local output_file="${2:-failure-analysis.md}"
    
    echo "# Test Failure Analysis Report" > "$output_file"
    echo "" >> "$output_file"
    echo "Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')" >> "$output_file"
    echo "" >> "$output_file"
    
    # Common error patterns
    declare -A error_patterns=(
        ["timeout"]="timeout|timed out|deadline exceeded"
        ["network"]="connection refused|network unreachable|could not resolve|API error"
        ["memory"]="cannot allocate memory|out of memory|memory exhausted"
        ["permission"]="permission denied|access denied|unauthorized"
        ["file_not_found"]="no such file|file not found|cannot find"
        ["api_rate_limit"]="rate limit|too many requests|429"
        ["compilation"]="compilation failed|undefined symbol|cannot compile"
        ["assertion"]="assertion failed|expect.*to be|should be"
    )
    
    # Count occurrences of each pattern
    echo "## Error Categories" >> "$output_file"
    echo "" >> "$output_file"
    
    for category in "${!error_patterns[@]}"; do
        pattern="${error_patterns[$category]}"
        count=$(grep -iE "$pattern" "$log_file" 2>/dev/null | wc -l)
        
        if [ $count -gt 0 ]; then
            echo "### $category errors: $count occurrences" >> "$output_file"
            echo "" >> "$output_file"
            
            # Get first few examples
            echo "Examples:" >> "$output_file"
            echo '```' >> "$output_file"
            grep -iE "$pattern" "$log_file" 2>/dev/null | head -3 >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"
        fi
    done
    
    # Extract specific test failures
    echo "## Failed Tests" >> "$output_file"
    echo "" >> "$output_file"
    
    # Look for R test failures
    if grep -q "FAIL" "$log_file" 2>/dev/null; then
        echo "### R Test Failures" >> "$output_file"
        echo '```' >> "$output_file"
        grep -A2 -B2 "FAIL" "$log_file" 2>/dev/null | head -20 >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi
    
    # Look for specific error messages
    echo "## Detailed Error Messages" >> "$output_file"
    echo "" >> "$output_file"
    
    # Extract error context
    if grep -q "Error:" "$log_file" 2>/dev/null; then
        echo '```' >> "$output_file"
        grep -A3 -B3 "Error:" "$log_file" 2>/dev/null | head -30 >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi
}

# Function to generate recommendations
generate_recommendations() {
    local analysis_file="$1"
    local recommendations_file="${2:-recommendations.md}"
    
    echo "## Recommendations" > "$recommendations_file"
    echo "" >> "$recommendations_file"
    
    # Check for specific issues and provide recommendations
    if grep -q "timeout errors:" "$analysis_file" 2>/dev/null; then
        echo "### Timeout Issues" >> "$recommendations_file"
        echo "- Consider increasing test timeout values" >> "$recommendations_file"
        echo "- Review tests for infinite loops or blocking operations" >> "$recommendations_file"
        echo "- Add timeout handling to long-running operations" >> "$recommendations_file"
        echo "" >> "$recommendations_file"
    fi
    
    if grep -q "network errors:" "$analysis_file" 2>/dev/null; then
        echo "### Network Issues" >> "$recommendations_file"
        echo "- Implement retry logic with exponential backoff" >> "$recommendations_file"
        echo "- Add network connectivity checks before tests" >> "$recommendations_file"
        echo "- Consider mocking external API calls" >> "$recommendations_file"
        echo "" >> "$recommendations_file"
    fi
    
    if grep -q "memory errors:" "$analysis_file" 2>/dev/null; then
        echo "### Memory Issues" >> "$recommendations_file"
        echo "- Use larger GitHub Actions runners" >> "$recommendations_file"
        echo "- Optimize memory usage in tests" >> "$recommendations_file"
        echo "- Add garbage collection calls between test suites" >> "$recommendations_file"
        echo "" >> "$recommendations_file"
    fi
    
    if grep -q "api_rate_limit errors:" "$analysis_file" 2>/dev/null; then
        echo "### API Rate Limit Issues" >> "$recommendations_file"
        echo "- Implement request caching" >> "$recommendations_file"
        echo "- Add delays between API calls" >> "$recommendations_file"
        echo "- Use API mocks for testing" >> "$recommendations_file"
        echo "" >> "$recommendations_file"
    fi
    
    # Append to analysis file
    cat "$recommendations_file" >> "$analysis_file"
}

# Function to check for known issues
check_known_issues() {
    local log_file="$1"
    local known_issues_file="${2:-.github/known-issues.json}"
    
    if [ ! -f "$known_issues_file" ]; then
        echo "[]" > "$known_issues_file"
    fi
    
    # Check each known issue pattern
    jq -r '.[] | "\(.id)|\(.pattern)|\(.description)"' "$known_issues_file" 2>/dev/null | while IFS='|' read -r id pattern description; do
        if grep -qE "$pattern" "$log_file" 2>/dev/null; then
            echo -e "${YELLOW}Known Issue Detected:${NC} $description (ID: $id)"
        fi
    done
}

# Main execution
main() {
    local log_file="${1:-}"
    local output_dir="${2:-.github/failure-analysis}"
    
    if [ -z "$log_file" ]; then
        echo "Usage: $0 <log_file> [output_dir]"
        exit 1
    fi
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}Error:${NC} Log file not found: $log_file"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Generate timestamp for this analysis
    timestamp=$(date +%Y%m%d_%H%M%S)
    analysis_file="$output_dir/analysis_$timestamp.md"
    
    echo -e "${GREEN}Analyzing failures in:${NC} $log_file"
    
    # Perform analysis
    analyze_error_patterns "$log_file" "$analysis_file"
    
    # Generate recommendations
    generate_recommendations "$analysis_file"
    
    # Check for known issues
    echo -e "\n${GREEN}Checking for known issues...${NC}"
    check_known_issues "$log_file"
    
    # Create summary for GitHub
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        {
            echo "## Test Failure Analysis"
            echo ""
            echo "Full analysis: [analysis_$timestamp.md]($analysis_file)"
            echo ""
            head -50 "$analysis_file"
        } >> "$GITHUB_STEP_SUMMARY"
    fi
    
    echo -e "\n${GREEN}Analysis complete:${NC} $analysis_file"
}

# Run main function
main "$@"