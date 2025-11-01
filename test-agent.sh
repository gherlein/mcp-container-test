#!/bin/bash

# Test script for the Bedrock Agent Service
# Usage: ./test-agent.sh [agent-url]

AGENT_URL=${1:-http://localhost:8000}

echo "Testing Bedrock Agent Service at $AGENT_URL"
echo "============================================="
echo ""

# Test 1: Health check
echo "1. Health Check"
echo "---------------"
response=$(curl -s -w "\n%{http_code}" "$AGENT_URL/health")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo "✓ Service is healthy"
    echo "$body" | jq .
else
    echo "✗ Health check failed (HTTP $http_code)"
    exit 1
fi
echo ""

# Test 2: List tools
echo "2. List Available Tools"
echo "-----------------------"
response=$(curl -s "$AGENT_URL/tools")
tool_count=$(echo "$response" | jq '.count')
echo "✓ Found $tool_count tools:"
echo "$response" | jq -r '.tools[].toolSpec.name' | sed 's/^/  - /'
echo ""

# Test 3: Simple calculation
echo "3. Test Calculator Tools"
echo "------------------------"
echo "Query: What is 25 * 4 + 10?"
response=$(curl -s -X POST "$AGENT_URL/agent/run" \
    -H "Content-Type: application/json" \
    -d '{
        "message": "What is 25 multiplied by 4, and then add 10 to the result?",
        "max_turns": 10
    }')

echo "Response:"
echo "$response" | jq -r '.response'
echo ""
echo "Tool calls made:"
echo "$response" | jq -r '.tool_calls[] | "  - \(.tool) with inputs: \(.input)"'
echo "Turns used: $(echo "$response" | jq -r '.turns')"
echo ""

# Test 4: Filesystem operations
echo "4. Test Filesystem Tools"
echo "------------------------"
echo "Query: Create a file called hello.txt with the content 'Hello from Bedrock Agent'"
response=$(curl -s -X POST "$AGENT_URL/agent/run" \
    -H "Content-Type: application/json" \
    -d '{
        "message": "Create a file called hello.txt with the content Hello from Bedrock Agent",
        "max_turns": 10
    }')

echo "Response:"
echo "$response" | jq -r '.response'
echo ""
echo "Tool calls made:"
echo "$response" | jq -r '.tool_calls[] | "  - \(.tool)"'
echo ""

# Test 5: Combined operations
echo "5. Test Combined Operations"
echo "---------------------------"
echo "Query: Calculate the square root of 144 and write it to a file"
response=$(curl -s -X POST "$AGENT_URL/agent/run" \
    -H "Content-Type: application/json" \
    -d '{
        "message": "Calculate the square root of 144 and write the result to a file called sqrt_result.txt",
        "max_turns": 10
    }')

echo "Response:"
echo "$response" | jq -r '.response'
echo ""
echo "Tool calls made:"
echo "$response" | jq -r '.tool_calls[] | "  - \(.tool)"'
echo ""

echo "============================================="
echo "All tests completed!"
