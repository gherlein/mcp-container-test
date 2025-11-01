#!/bin/bash

# AWS SSO Credentials to Environment File
# This script extracts temporary credentials from AWS SSO session
# and creates a .env file for container use
#
# Usage: ./scripts/sso-to-env.sh [profile-name]

PROFILE=${1:-default}

echo "======================================"
echo "AWS SSO Credentials Exporter"
echo "======================================"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI not found. Please install it first."
    exit 1
fi

# Check if profile exists
if ! aws configure list-profiles | grep -q "^${PROFILE}$"; then
    echo "Error: Profile '${PROFILE}' not found."
    echo ""
    echo "Available profiles:"
    aws configure list-profiles
    exit 1
fi

echo "Using profile: ${PROFILE}"
echo ""

# Check SSO login status
echo "Checking SSO login status..."
if ! aws sts get-caller-identity --profile "${PROFILE}" &>/dev/null; then
    echo "Not logged in to AWS SSO. Logging in now..."
    aws sso login --profile "${PROFILE}"

    if [ $? -ne 0 ]; then
        echo "Error: SSO login failed."
        exit 1
    fi
fi

echo "✓ SSO login successful"
echo ""

# Get caller identity
echo "Logged in as:"
aws sts get-caller-identity --profile "${PROFILE}"
echo ""

# Export credentials to environment variables
echo "Exporting credentials..."
eval $(aws configure export-credentials --profile "${PROFILE}" --format env)

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "Error: Failed to export credentials"
    exit 1
fi

echo "✓ Credentials exported"
echo ""

# Get region
REGION=$(aws configure get region --profile "${PROFILE}" 2>/dev/null)
if [ -z "$REGION" ]; then
    REGION="us-east-1"
    echo "⚠ No region configured, using default: ${REGION}"
fi

# Create or update .env file
echo "Creating .env file..."

cat > .env <<EOF
# AWS Credentials from SSO (Profile: ${PROFILE})
# Generated: $(date)
# These credentials are temporary and will expire!

AWS_REGION=${REGION}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}

# Bedrock Configuration
BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0

# MCP Server URLs (for local development)
MCP_FILESYSTEM_URL=http://mcp-filesystem:3001
MCP_CALCULATOR_URL=http://mcp-calculator:3002
EOF

echo "✓ .env file created"
echo ""

# Check expiration
echo "Checking credential expiration..."
EXPIRATION=$(aws configure export-credentials --profile "${PROFILE}" --format json | jq -r '.Expiration // empty' 2>/dev/null)

if [ -n "$EXPIRATION" ]; then
    echo "⚠ WARNING: These credentials will expire at: ${EXPIRATION}"
    echo ""
    echo "You will need to run this script again after expiration."
else
    echo "ℹ Could not determine expiration time"
fi

echo ""
echo "======================================"
echo "Credentials exported successfully!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  1. Restart containers: make down && make up"
echo "  2. Test: ./test-agent.sh"
echo ""
echo "Note: SSO credentials are temporary."
echo "Re-run this script when they expire."
