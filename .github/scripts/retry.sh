#!/bin/bash
# Retry script with exponential backoff for GitHub Actions

set -e

# Default values
MAX_RETRIES=3
TIMEOUT=300  # 5 minutes default

# Parse arguments
COMMAND=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    *)
      COMMAND="$@"
      break
      ;;
  esac
done

if [ -z "$COMMAND" ]; then
  echo "Usage: $0 [--max-retries N] [--timeout SECONDS] command [args...]"
  exit 1
fi

echo "Running command with retry (max retries: $MAX_RETRIES, timeout: ${TIMEOUT}s)"
echo "Command: $COMMAND"

for i in $(seq 1 $MAX_RETRIES); do
  echo "Attempt $i of $MAX_RETRIES..."
  
  if timeout $TIMEOUT bash -c "$COMMAND"; then
    echo "Command succeeded on attempt $i"
    exit 0
  else
    exit_code=$?
    echo "Command failed with exit code $exit_code on attempt $i"
    
    if [ $i -lt $MAX_RETRIES ]; then
      sleep_time=$((2 ** i))
      echo "Retrying in ${sleep_time} seconds..."
      sleep $sleep_time
    fi
  fi
done

echo "Command failed after $MAX_RETRIES attempts"
exit 1