#!/bin/bash

# Setup script for API key configuration
# This script helps you securely set up your RAPIDAPI_KEY

echo "==================================="
echo "League Simulator API Key Setup"
echo "==================================="
echo ""

# Check if .Renviron already exists
if [ -f ".Renviron" ]; then
    echo "⚠️  .Renviron file already exists!"
    echo "Current content:"
    echo "---"
    grep -E "^[^#]" .Renviron | grep -v "KEY" | head -5
    echo "---"
    read -p "Do you want to update it? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Get API key from user
echo ""
echo "Please enter your RAPIDAPI_KEY:"
echo "(You can find it at: https://rapidapi.com/api-sports/api/api-football)"
read -s RAPIDAPI_KEY

# Validate key
if [ -z "$RAPIDAPI_KEY" ]; then
    echo "❌ Error: API key cannot be empty"
    exit 1
fi

# Create or update .Renviron
echo "" >> .Renviron
echo "# API-Football access via RapidAPI" >> .Renviron
echo "RAPIDAPI_KEY=$RAPIDAPI_KEY" >> .Renviron

echo ""
echo "✅ API key saved to .Renviron"
echo ""
echo "To use it in R:"
echo "  - Restart your R session"
echo "  - Or run: readRenviron('.Renviron')"
echo ""
echo "To verify:"
echo "  Rscript -e \"cat('API Key set:', Sys.getenv('RAPIDAPI_KEY') != '', '\n')\""
echo ""
echo "⚠️  Remember: Never commit .Renviron to git!"
echo "    (.gitignore already includes it)"