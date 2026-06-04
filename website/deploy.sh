#!/bin/bash

# BASANS Website Deployment Script
# Deploys to surge.sh

echo "========================================"
echo "BASANS Website Deployment"
echo "========================================"

# Check if surge is installed
if ! command -v surge &> /dev/null; then
    echo "ERROR: surge not found"
    echo ""
    echo "Install surge globally:"
    echo "  npm install -g surge"
    echo ""
    exit 1
fi

# Check if we're in the website directory
if [ ! -f "index.html" ]; then
    echo "ERROR: index.html not found"
    echo "Please run this script from the website directory"
    exit 1
fi

echo "Deploying to surge.sh..."
echo ""

# Deploy to surge
surge . basans.surge.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "SUCCESS: Website deployed!"
    echo "URL: https://basans.surge.sh"
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo "ERROR: Deployment failed"
    echo "========================================"
fi
