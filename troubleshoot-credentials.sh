#!/bin/bash

# Troubleshooting script for AWS credentials
# Usage: ./troubleshoot-credentials.sh

echo "======================================"
echo "AWS Credentials Troubleshooting"
echo "======================================"
echo ""

# Check if .env file exists
echo "1. Checking .env file..."
if [ -f .env ]; then
    echo "✓ .env file exists"
    echo ""
    echo "Contents (with secrets masked):"
    while IFS= read -r line; do
        if [[ $line =~ ^AWS_ACCESS_KEY_ID=.+ ]]; then
            echo "AWS_ACCESS_KEY_ID=***masked***"
        elif [[ $line =~ ^AWS_SECRET_ACCESS_KEY=.+ ]]; then
            echo "AWS_SECRET_ACCESS_KEY=***masked***"
        elif [[ $line =~ ^AWS_SESSION_TOKEN=.+ ]]; then
            echo "AWS_SESSION_TOKEN=***masked***"
        elif [[ $line =~ ^AWS.* ]]; then
            echo "$line"
        fi
    done < .env
else
    echo "✗ .env file NOT found!"
    echo ""
    echo "Create it with:"
    echo "  cp .env.example .env"
    echo "  # Then edit .env with your AWS credentials"
    exit 1
fi

echo ""
echo "2. Checking if agent-service container is running..."
if podman ps --format "{{.Names}}" | grep -q "agent-service"; then
    echo "✓ agent-service container is running"
else
    echo "✗ agent-service container is NOT running"
    echo ""
    echo "Start it with:"
    echo "  make up"
    exit 1
fi

echo ""
echo "3. Checking environment variables in container..."
AWS_VARS=$(podman exec agent-service printenv | grep -E "^AWS_")

if [ -n "$AWS_VARS" ]; then
    echo "✓ AWS environment variables found in container:"
    echo ""
    echo "$AWS_VARS" | while read -r line; do
        var_name=$(echo "$line" | cut -d= -f1)
        var_value=$(echo "$line" | cut -d= -f2-)

        if [[ $var_name == "AWS_ACCESS_KEY_ID" ]] || [[ $var_name == "AWS_SECRET_ACCESS_KEY" ]] || [[ $var_name == "AWS_SESSION_TOKEN" ]]; then
            if [ -n "$var_value" ]; then
                echo "  $var_name=***masked (${#var_value} chars)***"
            else
                echo "  $var_name=(EMPTY - THIS IS A PROBLEM!)"
            fi
        else
            echo "  $line"
        fi
    done
else
    echo "✗ NO AWS environment variables found in container!"
    echo ""
    echo "This means the .env file is not being loaded."
    echo ""
    echo "Fix:"
    echo "  1. Stop containers: make down"
    echo "  2. Verify .env file has credentials"
    echo "  3. Start containers: make up"
fi

echo ""
echo "4. Testing AWS credentials..."
if podman exec agent-service python3 -c "import boto3; print(boto3.client('sts', region_name='us-east-1').get_caller_identity())" 2>&1 | grep -q "Account"; then
    echo "✓ AWS credentials are valid!"
    echo ""
    podman exec agent-service python3 -c "import boto3; print(boto3.client('sts', region_name='us-east-1').get_caller_identity())" 2>/dev/null
else
    echo "✗ AWS credentials test FAILED"
    echo ""
    echo "Error details:"
    podman exec agent-service python3 -c "import boto3; print(boto3.client('sts', region_name='us-east-1').get_caller_identity())" 2>&1 || true
fi

echo ""
echo "5. Checking Bedrock access..."
if podman exec agent-service python3 -c "import boto3; boto3.client('bedrock-runtime', region_name='us-east-1').list_foundation_models()" 2>&1 | grep -q "Error"; then
    echo "✗ Cannot access Bedrock"
    echo ""
    echo "Possible issues:"
    echo "  - Bedrock not enabled in your AWS account"
    echo "  - Region doesn't support Bedrock (try us-east-1 or us-west-2)"
    echo "  - IAM permissions missing"
else
    echo "✓ Bedrock access working!"
fi

echo ""
echo "======================================"
echo "Troubleshooting Complete"
echo "======================================"
