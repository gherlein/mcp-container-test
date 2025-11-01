#!/bin/bash

# Quick Start Script for AWS SSO Users
# This script automates the SSO login and credential export process
#
# Usage: ./start-with-sso.sh [profile-name]

set -e

PROFILE=${1:-default}

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   Bedrock Agent - AWS SSO Quick Start     ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v aws &> /dev/null; then
    echo "✗ AWS CLI not found. Please install it first."
    exit 1
fi

if ! command -v podman &> /dev/null; then
    echo "✗ Podman not found. Please install it first."
    exit 1
fi

echo "✓ Prerequisites OK"
echo ""

# Step 1: Login to SSO
echo "Step 1/5: AWS SSO Login"
echo "-----------------------"
echo "Profile: $PROFILE"
echo ""

if aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
    echo "✓ Already logged in to AWS SSO"
else
    echo "Not logged in. Opening browser for SSO login..."
    aws sso login --profile "$PROFILE"
fi

echo ""

# Step 2: Export credentials
echo "Step 2/5: Export Credentials"
echo "-----------------------------"
./scripts/sso-to-env.sh "$PROFILE"
echo ""

# Step 3: Stop any running containers
echo "Step 3/5: Stop Existing Containers"
echo "-----------------------------------"
if podman ps | grep -q "agent-service\|mcp-filesystem\|mcp-calculator"; then
    echo "Stopping existing containers..."
    make down 2>/dev/null || true
    echo "✓ Containers stopped"
else
    echo "✓ No containers running"
fi
echo ""

# Step 4: Build images if needed
echo "Step 4/5: Build Images"
echo "----------------------"
if podman images | grep -q "localhost/agent-service"; then
    echo "✓ Images already built"
else
    echo "Building images (this may take a few minutes)..."
    make build
fi
echo ""

# Step 5: Start services
echo "Step 5/5: Start Services"
echo "------------------------"
make up

echo ""
echo "Waiting for services to start..."
sleep 5

# Check if services are running
if podman ps | grep -q "agent-service"; then
    echo "✓ Services started successfully!"
else
    echo "✗ Failed to start services. Check logs with: make logs"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║            Setup Complete! 🎉              ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "Services running at:"
echo "  • Agent Service:    http://localhost:8000"
echo "  • Filesystem MCP:   http://localhost:3001"
echo "  • Calculator MCP:   http://localhost:3002"
echo ""
echo "Next steps:"
echo "  1. Test the agent:  ./test-agent.sh"
echo "  2. View logs:       make logs"
echo "  3. Stop services:   make down"
echo ""
echo "⚠ Important: SSO credentials are temporary!"
echo "   They will expire. When they do, re-run this script:"
echo "   ./start-with-sso.sh $PROFILE"
echo ""
