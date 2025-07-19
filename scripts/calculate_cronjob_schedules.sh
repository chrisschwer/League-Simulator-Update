#!/bin/bash
# Timezone Calculation Script for CronJob Schedules
# Converts Berlin times to UTC for both standard time (CET) and daylight saving time (CEST)

set -e

calculate_utc_schedule() {
    local berlin_time="$1"
    local season="$2"  # "winter" (CET, UTC+1) or "summer" (CEST, UTC+2)
    
    local hour="${berlin_time%:*}"
    local minute="${berlin_time#*:}"
    
    # Remove leading zeros to avoid octal interpretation
    hour=$((10#$hour))
    minute=$((10#$minute))
    
    local utc_hour
    if [[ "$season" == "winter" ]]; then
        # CET: UTC = Berlin - 1 hour
        utc_hour=$((hour - 1))
    else
        # CEST: UTC = Berlin - 2 hours  
        utc_hour=$((hour - 2))
    fi
    
    # Handle day rollover
    if [[ $utc_hour -lt 0 ]]; then
        utc_hour=$((utc_hour + 24))
    fi
    
    printf "%02d %02d" "$minute" "$utc_hour"
}

# Test timezone calculations
test_timezone_calculations() {
    echo "Testing timezone calculations..."
    
    # Test individual cases
    test_single_calculation "17:15" "winter" "15 16" "BL weekend start"
    test_single_calculation "19:30" "winter" "30 18" "BL weekday start"
    test_single_calculation "14:50" "winter" "50 13" "BL2 weekend start"
    test_single_calculation "17:15" "summer" "15 15" "BL weekend start (summer)"
    test_single_calculation "19:30" "summer" "30 17" "BL weekday start (summer)"
    test_single_calculation "14:50" "summer" "50 12" "BL2 weekend start (summer)"
    
    echo "All timezone calculations passed!"
}

test_single_calculation() {
    local berlin_time="$1"
    local season="$2"
    local expected="$3"
    local description="$4"
    
    local actual=$(calculate_utc_schedule "$berlin_time" "$season")
    
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $description ($berlin_time $season)"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        return 1
    else
        echo "PASS: $description ($berlin_time $season) → $actual UTC"
    fi
}

# Generate all CronJob schedules
generate_all_schedules() {
    echo "Generating all CronJob schedules..."
    echo "Format: 'minute hour * * dayofweek'"
    echo ""
    
    # Bundesliga schedules
    echo "=== Bundesliga (BL) ==="
    echo "Weekend Start (17:15): $(calculate_utc_schedule '17:15' 'summer') * * 0,6 (summer)"
    echo "Weekend Start (17:15): $(calculate_utc_schedule '17:15' 'winter') * * 0,6 (winter)"
    echo "Weekend Stop  (21:50): $(calculate_utc_schedule '21:50' 'summer') * * 0,6 (summer)"
    echo "Weekend Stop  (21:50): $(calculate_utc_schedule '21:50' 'winter') * * 0,6 (winter)"
    echo "Weekday Start (19:25): $(calculate_utc_schedule '19:25' 'summer') * * 1-5 (summer)"
    echo "Weekday Start (19:25): $(calculate_utc_schedule '19:25' 'winter') * * 1-5 (winter)"
    echo "Weekday Stop  (23:35): $(calculate_utc_schedule '23:35' 'summer') * * 1-5 (summer)"
    echo "Weekday Stop  (23:35): $(calculate_utc_schedule '23:35' 'winter') * * 1-5 (winter)"
    echo ""
    
    # 2. Bundesliga schedules
    echo "=== 2. Bundesliga (BL2) ==="
    echo "Weekend Start (14:45): $(calculate_utc_schedule '14:45' 'summer') * * 0,6 (summer)"
    echo "Weekend Start (14:45): $(calculate_utc_schedule '14:45' 'winter') * * 0,6 (winter)"
    echo "Weekend Stop  (23:05): $(calculate_utc_schedule '23:05' 'summer') * * 0,6 (summer)"
    echo "Weekend Stop  (23:05): $(calculate_utc_schedule '23:05' 'winter') * * 0,6 (winter)"
    echo "Weekday Start (19:25): $(calculate_utc_schedule '19:25' 'summer') * * 1-5 (summer)"
    echo "Weekday Start (19:25): $(calculate_utc_schedule '19:25' 'winter') * * 1-5 (winter)"
    echo "Weekday Stop  (23:35): $(calculate_utc_schedule '23:35' 'summer') * * 1-5 (summer)"
    echo "Weekday Stop  (23:35): $(calculate_utc_schedule '23:35' 'winter') * * 1-5 (winter)"
    echo ""
    
    # 3. Liga schedules
    echo "=== 3. Liga ==="
    echo "Weekend Start (15:15): $(calculate_utc_schedule '15:15' 'summer') * * 0,6 (summer)"
    echo "Weekend Start (15:15): $(calculate_utc_schedule '15:15' 'winter') * * 0,6 (winter)"
    echo "Weekend Stop  (22:05): $(calculate_utc_schedule '22:05' 'summer') * * 0,6 (summer)"
    echo "Weekend Stop  (22:05): $(calculate_utc_schedule '22:05' 'winter') * * 0,6 (winter)"
    echo "Weekday Start (19:15): $(calculate_utc_schedule '19:15' 'summer') * * 1-5 (summer)"
    echo "Weekday Start (19:15): $(calculate_utc_schedule '19:15' 'winter') * * 1-5 (winter)"
    echo "Weekday Stop  (23:05): $(calculate_utc_schedule '23:05' 'summer') * * 1-5 (summer)"
    echo "Weekday Stop  (23:05): $(calculate_utc_schedule '23:05' 'winter') * * 1-5 (winter)"
    echo ""
    
    # Shiny schedules
    echo "=== Shiny Updater ==="
    echo "Daily Start (14:40): $(calculate_utc_schedule '14:40' 'summer') * * * (summer)"
    echo "Daily Start (14:40): $(calculate_utc_schedule '14:40' 'winter') * * * (winter)"
    echo "Daily Stop  (23:40): $(calculate_utc_schedule '23:40' 'summer') * * * (summer)"
    echo "Daily Stop  (23:40): $(calculate_utc_schedule '23:40' 'winter') * * * (winter)"
}

# Main function
main() {
    case "${1:-}" in
        "test")
            test_timezone_calculations
            ;;
        "generate")
            generate_all_schedules
            ;;
        "calculate")
            if [[ $# -ne 3 ]]; then
                echo "Usage: $0 calculate <berlin_time> <season>"
                echo "Example: $0 calculate 17:15 summer"
                exit 1
            fi
            calculate_utc_schedule "$2" "$3"
            ;;
        *)
            echo "Usage: $0 {test|generate|calculate <time> <season>}"
            echo ""
            echo "Commands:"
            echo "  test      - Run timezone calculation tests"
            echo "  generate  - Generate all CronJob schedules"
            echo "  calculate - Calculate specific UTC time"
            echo ""
            echo "Examples:"
            echo "  $0 test"
            echo "  $0 generate"
            echo "  $0 calculate 17:15 summer"
            exit 1
            ;;
    esac
}

main "$@"