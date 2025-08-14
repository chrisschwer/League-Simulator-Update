#!/bin/sh
# Robust startup script for integrated League Simulator with Rust engine

set -e

# Configuration
MAX_RETRIES=5
RETRY_DELAY=30
RUST_HEALTH_CHECK_RETRIES=10

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    if [ ! -z "$RUST_PID" ]; then
        echo "Stopping Rust server (PID: $RUST_PID)..."
        kill $RUST_PID 2>/dev/null || true
        wait $RUST_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Function to start Rust server
start_rust_server() {
    echo "Starting Rust simulation engine..."
    /usr/local/bin/league-simulator-rust --api &
    RUST_PID=$!
    
    echo "Waiting for Rust server to start (PID: $RUST_PID)..."
    for i in $(seq 1 $RUST_HEALTH_CHECK_RETRIES); do
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            echo "✅ Rust server ready on port 8080"
            return 0
        fi
        echo "  Attempt $i/$RUST_HEALTH_CHECK_RETRIES - waiting..."
        sleep 1
    done
    
    echo "❌ ERROR: Rust server failed to start after $RUST_HEALTH_CHECK_RETRIES attempts"
    return 1
}

# Function to run R scheduler with retries
run_scheduler() {
    cd /app
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo ""
        echo "========================================="
        echo "Starting R scheduler (attempt $attempt/$MAX_RETRIES)"
        echo "========================================="
        
        # Ensure Rust server is running
        if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
            echo "⚠️ Rust server not responding, restarting..."
            if [ ! -z "$RUST_PID" ]; then
                kill $RUST_PID 2>/dev/null || true
                wait $RUST_PID 2>/dev/null || true
            fi
            if ! start_rust_server; then
                echo "Failed to restart Rust server"
                return 1
            fi
        fi
        
        # Run the scheduler
        export RUST_API_URL=http://localhost:8080
        Rscript RCode/updateSchedulerRust.R
        EXIT_CODE=$?
        
        if [ $EXIT_CODE -eq 0 ]; then
            echo "✅ Scheduler completed successfully"
            return 0
        else
            echo "⚠️ Scheduler failed with exit code $EXIT_CODE"
            
            # Check if Rust server is still alive
            if ! kill -0 $RUST_PID 2>/dev/null; then
                echo "❌ Rust server crashed"
            fi
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "Waiting $RETRY_DELAY seconds before retry..."
                sleep $RETRY_DELAY
            fi
        fi
    done
    
    echo "❌ ERROR: Scheduler failed after $MAX_RETRIES attempts"
    return 1
}

# Main execution
echo "==================================================="
echo "League Simulator Integrated - Rust + R"
echo "==================================================="
echo "Season: ${SEASON:-auto-detect}"
echo "API Key: ${RAPIDAPI_KEY:0:10}..."
echo ""

# Start Rust server
if ! start_rust_server; then
    echo "Failed to start Rust server"
    exit 1
fi

# Run scheduler with retries
run_scheduler
EXIT_CODE=$?

# Cleanup handled by trap
exit $EXIT_CODE