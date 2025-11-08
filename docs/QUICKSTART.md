# Quick Start Guide

Get the Bedrock Agent system running in 5 minutes!

## Prerequisites

- Podman & podman-compose installed (or use `podman compose`)
- AWS account with Bedrock access
- AWS CLI configured with credentials

**Using AWS SSO?** See the [SSO Quick Start](#sso-quick-start) below or [AWS_SSO_SETUP.md](AWS_SSO_SETUP.md)

## Step 1: Configure AWS Credentials

Copy the example environment file and add your AWS credentials:

```bash
cp .env.example .env
```

Edit `.env` and set:
```bash
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
```

## Step 2: Start the Services

```bash
# Build and start all services
make build
make up

# Or using podman-compose directly
podman-compose -f podman-compose.yml up -d

# Or using podman compose (newer syntax)
podman compose -f podman-compose.yml up -d

# Alternative: Use native Podman pods
make pod-create && make pod-start
```

Wait about 30 seconds for all services to start.

## Step 3: Test the Agent

Run the automated test suite:

```bash
./test-agent.sh
```

Or test manually:

```bash
# Check health
curl http://localhost:8000/health

# Run a query
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is 100 divided by 4?"
  }'
```

## Example Queries to Try

### Math Operations
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Calculate the square root of 256 and then multiply by 3"
  }'
```

### File Operations
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Create a file called notes.txt with the content: Meeting at 3pm"
  }'
```

### List Files
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "List all files in the workspace directory"
  }'
```

### Combined Operations
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Calculate 15 times 7, then write the result to a file called calculation.txt"
  }'
```

## View Logs

```bash
# All services
make logs

# Or specific service with podman-compose
podman-compose -f podman-compose.yml logs -f agent-service

# Or with podman pod
podman pod logs bedrock-agent-pod
```

## Stop Services

```bash
# With compose
make down

# With pod
make pod-stop
make pod-remove
```

## Troubleshooting

### "Connection refused" errors
- Wait a bit longer for services to start
- Check if containers are running: `podman ps`
- Check if pod is running: `podman pod ps`

### "Access Denied" from Bedrock
- Verify your AWS credentials are correct
- Check your IAM user has Bedrock permissions
- Ensure Bedrock is available in your region

### MCP servers not responding
- Check logs: `podman logs mcp-filesystem`
- Restart services: `make down && make up`
- Or restart pod: `make pod-stop && make pod-start`

### Permission issues with volumes
- Podman runs rootless by default
- Ensure the workspace directory has correct permissions
- The `:Z` flag in volume mounts handles SELinux contexts

## SSO Quick Start

If you use AWS SSO for authentication:

```bash
# Option 1: One-command Makefile target (Recommended)
aws sso login --profile your-profile
make up-sso PROFILE=your-profile

# Option 2: Automated script
./start-with-sso.sh your-profile

# Option 3: Manual steps
aws sso login --profile your-profile
make sso-export PROFILE=your-profile
make down && make up
./test-agent.sh
```

**Note:** SSO credentials are temporary (usually expire in 1-12 hours). Re-run when they expire.

See [AWS_SSO_SETUP.md](AWS_SSO_SETUP.md) for detailed SSO setup instructions.

## Next Steps

- Read the full [README.md](README.md) for EKS deployment
- Add custom MCP servers for your use case
- Explore different Bedrock models
- Set up monitoring and logging

## Useful Commands

```bash
# View all available commands
make help

# Rebuild after code changes
make build && make up

# Clean everything
make clean
```

## Need Help?

Check the main [README.md](README.md) for detailed documentation and troubleshooting.
