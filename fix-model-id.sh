#!/bin/bash

# Quick fix script for Bedrock model ID issue
# This script updates the model ID from old format to new inference profile format

set -e

echo "════════════════════════════════════════════"
echo "Bedrock Model ID Fix Script"
echo "════════════════════════════════════════════"
echo ""
echo "This script will update your .env file to use the new"
echo "Bedrock inference profile format."
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "✗ .env file not found!"
    echo ""
    echo "Creating .env from .env.example..."
    cp .env.example .env
    echo "✓ .env file created"
    echo ""
    echo "Please edit .env and add your AWS credentials, then run this script again."
    exit 1
fi

echo "Current .env file:"
echo "─────────────────────────────────────────────"
grep BEDROCK_MODEL_ID .env || echo "(BEDROCK_MODEL_ID not found)"
echo "─────────────────────────────────────────────"
echo ""

# Check if old format is being used
if grep -q "BEDROCK_MODEL_ID=anthropic.claude-3" .env; then
    echo "⚠ Old model ID format detected!"
    echo ""
    echo "Updating to new inference profile format..."

    # Backup .env
    cp .env .env.backup
    echo "✓ Backed up .env to .env.backup"

    # Update the model ID
    sed -i.tmp 's/BEDROCK_MODEL_ID=anthropic\.claude-3-5-sonnet-20241022-v2:0/BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0/g' .env
    sed -i.tmp 's/BEDROCK_MODEL_ID=anthropic\.claude-3-5-sonnet-20240620-v1:0/BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20240620-v1:0/g' .env
    sed -i.tmp 's/BEDROCK_MODEL_ID=anthropic\.claude-3-opus-20240229-v1:0/BEDROCK_MODEL_ID=us.anthropic.claude-3-opus-20240229-v1:0/g' .env
    sed -i.tmp 's/BEDROCK_MODEL_ID=anthropic\.claude-3-sonnet-20240229-v1:0/BEDROCK_MODEL_ID=us.anthropic.claude-3-sonnet-20240229-v1:0/g' .env
    sed -i.tmp 's/BEDROCK_MODEL_ID=anthropic\.claude-3-haiku-20240307-v1:0/BEDROCK_MODEL_ID=us.anthropic.claude-3-haiku-20240307-v1:0/g' .env
    rm -f .env.tmp

    echo "✓ Updated model ID"
    echo ""
elif grep -q "BEDROCK_MODEL_ID=us\.anthropic\.claude-3" .env || grep -q "BEDROCK_MODEL_ID=eu\.anthropic\.claude-3" .env; then
    echo "✓ Model ID is already in correct format!"
    echo ""
else
    echo "⚠ Could not determine current model ID format"
    echo ""
    echo "Adding recommended model ID..."

    # Backup .env
    cp .env .env.backup
    echo "✓ Backed up .env to .env.backup"

    # Add or update the model ID
    if grep -q "BEDROCK_MODEL_ID=" .env; then
        sed -i.tmp 's/BEDROCK_MODEL_ID=.*/BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0/' .env
        rm -f .env.tmp
    else
        echo "" >> .env
        echo "# Bedrock Configuration" >> .env
        echo "BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0" >> .env
    fi

    echo "✓ Added model ID"
    echo ""
fi

echo "Updated .env file:"
echo "─────────────────────────────────────────────"
grep BEDROCK_MODEL_ID .env
echo "─────────────────────────────────────────────"
echo ""

echo "════════════════════════════════════════════"
echo "Fix Complete!"
echo "════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Restart containers: make down && make up"
echo "  2. Test the agent:     ./test-agent.sh"
echo ""
echo "If you need to use a different model, edit .env and change"
echo "BEDROCK_MODEL_ID to one of these:"
echo ""
echo "  • us.anthropic.claude-3-5-sonnet-20241022-v2:0 (recommended)"
echo "  • us.anthropic.claude-3-5-sonnet-20240620-v1:0"
echo "  • us.anthropic.claude-3-opus-20240229-v1:0"
echo "  • us.anthropic.claude-3-haiku-20240307-v1:0"
echo ""
echo "See BEDROCK_MODEL_UPDATE.md for more information."
echo ""
