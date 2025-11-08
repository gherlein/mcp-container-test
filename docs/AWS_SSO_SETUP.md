# AWS SSO Setup Guide

This guide explains how to use AWS SSO credentials with the Bedrock Agent containers.

## The Problem

AWS SSO creates temporary credentials that are stored in `~/.aws/credentials` under a profile. These aren't available as environment variables, so containers can't access them by default.

## Solution Options

You have 3 options to use AWS SSO with containers:

### Option 1: Export SSO Credentials to .env (Recommended)

Use the provided script to extract temporary credentials:

```bash
# If your SSO profile is "default"
./scripts/sso-to-env.sh

# Or specify a different profile
./scripts/sso-to-env.sh my-sso-profile
```

This script will:
1. Check if you're logged in to SSO (and login if needed)
2. Extract temporary credentials
3. Create a `.env` file with the credentials
4. Show when the credentials will expire

Then restart containers:

```bash
make down
make up
```

**Pros:**
- ✅ Works with standard podman-compose.yml
- ✅ Simple and straightforward
- ✅ No container modifications needed

**Cons:**
- ❌ Credentials expire (usually 1-12 hours)
- ❌ Must re-run script when they expire

### Option 2: Mount ~/.aws Directory (Alternative)

Use the SSO-specific compose file that mounts your AWS directory:

```bash
# Make sure you're logged in to SSO
aws sso login --profile your-profile

# Use the SSO compose file
podman-compose -f podman-compose-sso.yml up -d

# Set your profile
export AWS_PROFILE=your-profile
podman-compose -f podman-compose-sso.yml up -d
```

Or with Make:

```bash
# Create a Makefile target
make sso-up PROFILE=your-profile
```

**Pros:**
- ✅ Credentials auto-refresh from SSO session
- ✅ No need to re-export when they expire
- ✅ Uses your actual SSO session

**Cons:**
- ❌ Must keep SSO session active (`aws sso login`)
- ❌ Mounts home directory into container
- ❌ Requires different compose file

### Option 3: Automated Refresh Script

Set up a script to automatically refresh credentials:

```bash
# Create a cron job or systemd timer
*/30 * * * * /path/to/scripts/sso-to-env.sh && cd /path/to/project && make down && make up
```

**Pros:**
- ✅ Fully automated
- ✅ Credentials stay fresh

**Cons:**
- ❌ More complex setup
- ❌ Restarts containers periodically

## Detailed Setup Instructions

### Quick Start (Option 1)

**One-Command Method:**
```bash
# Login first (if not already logged in)
aws sso login --profile your-profile

# Then use the convenient up-sso command
make up-sso PROFILE=your-profile
```

**Manual Method:**
```bash
# 1. Login to AWS SSO
aws sso login --profile your-profile

# 2. Export credentials to .env
./scripts/sso-to-env.sh your-profile

# 3. Start containers
make down
make up

# 4. Test
./test-agent.sh
```

### Alternative Setup (Option 2)

```bash
# 1. Login to AWS SSO
aws sso login --profile your-profile

# 2. Set environment variable
export AWS_PROFILE=your-profile

# 3. Start with SSO compose file
podman-compose -f podman-compose-sso.yml up -d

# 4. Test
./test-agent.sh
```

## Understanding SSO Credential Expiration

SSO credentials are temporary and expire after a set time (usually 1-12 hours).

### Check When Credentials Expire

```bash
# Using AWS CLI
aws configure export-credentials --profile your-profile --format json | jq -r '.Expiration'

# Using the script (shows expiration automatically)
./scripts/sso-to-env.sh your-profile
```

### What Happens When Credentials Expire

You'll see errors like:
- "ExpiredToken: The security token included in the request is expired"
- "Unable to locate credentials"
- "An error occurred (UnrecognizedClientException)"

### Refresh Expired Credentials

**Option 1 method:**
```bash
# Re-run the script
./scripts/sso-to-env.sh your-profile

# Restart containers
make down && make up
```

**Option 2 method:**
```bash
# Re-login to SSO
aws sso login --profile your-profile

# Containers automatically pick up new credentials (no restart needed)
```

## Checking SSO Login Status

```bash
# Test if you're logged in
aws sts get-caller-identity --profile your-profile

# If you get an error, login again
aws sso login --profile your-profile
```

## Troubleshooting

### "Error loading SSO Token"

**Solution:**
```bash
# Login to SSO
aws sso login --profile your-profile
```

### "Unable to locate credentials" in container

**Option 1 users:**
```bash
# Re-export credentials
./scripts/sso-to-env.sh your-profile
make down && make up
```

**Option 2 users:**
```bash
# Check if ~/.aws is mounted
podman exec agent-service ls -la /root/.aws

# Re-login to SSO
aws sso login --profile your-profile

# Restart containers
podman-compose -f podman-compose-sso.yml restart agent-service
```

### Credentials work locally but not in container

```bash
# Verify environment variables in container
podman exec agent-service printenv | grep AWS

# Should show:
# AWS_REGION=...
# AWS_ACCESS_KEY_ID=...
# AWS_SECRET_ACCESS_KEY=...
# AWS_SESSION_TOKEN=...

# Test credentials in container
podman exec agent-service python3 -c "import boto3; print(boto3.client('sts').get_caller_identity())"
```

### "SSO session has expired"

```bash
# Login again
aws sso login --profile your-profile

# Then re-export (Option 1)
./scripts/sso-to-env.sh your-profile
make down && make up
```

## Recommended Workflow

For daily development with SSO, I recommend:

```bash
#!/bin/bash
# Save as: start-dev.sh

# 1. Login to SSO
echo "Logging in to AWS SSO..."
aws sso login --profile your-profile

# 2. Export credentials
echo "Exporting credentials..."
./scripts/sso-to-env.sh your-profile

# 3. Start services
echo "Starting services..."
make down
make up

# 4. Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# 5. Test
echo "Testing agent..."
./test-agent.sh

echo ""
echo "Development environment ready!"
echo "Remember: SSO credentials expire. Re-run this script when they do."
```

Make it executable:
```bash
chmod +x start-dev.sh
./start-dev.sh
```

## Using with EKS Deployment

For EKS, you should NOT use SSO credentials. Instead:

1. **Use IRSA (IAM Roles for Service Accounts)** - Recommended
   - Already configured in `k8s/serviceaccount.yaml`
   - Containers automatically get credentials from IAM role

2. **Use permanent IAM user credentials** - For testing only
   - Create IAM user with Bedrock permissions
   - Use access key/secret (not SSO)

## Security Best Practices

1. **Never commit .env file**
   - Already in `.gitignore`
   - Contains sensitive temporary credentials

2. **Use Option 2 for local dev only**
   - Mounting `~/.aws` is convenient but less secure
   - Don't use in production

3. **Rotate SSO sessions regularly**
   - Login at start of each work session
   - Don't leave sessions active for days

4. **Use shortest credential duration**
   ```bash
   # Configure in ~/.aws/config
   [profile your-profile]
   sso_start_url = https://your-org.awsapps.com/start
   sso_region = us-east-1
   sso_account_id = 123456789012
   sso_role_name = YourRole
   region = us-east-1
   duration_seconds = 3600  # 1 hour (minimum)
   ```

## Alternative: Use aws-vault

If you use `aws-vault` for SSO management:

```bash
# Export credentials with aws-vault
aws-vault exec your-profile -- bash -c 'cat > .env <<EOF
AWS_REGION=${AWS_REGION}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}
BEDROCK_MODEL_ID=anthropic.claude-3-5-sonnet-20241022-v2:0
MCP_FILESYSTEM_URL=http://mcp-filesystem:3001
MCP_CALCULATOR_URL=http://mcp-calculator:3002
EOF'

# Start containers
make down && make up
```

## Comparison Table

| Feature | Option 1: Export to .env | Option 2: Mount ~/.aws |
|---------|-------------------------|------------------------|
| Setup complexity | Simple | Moderate |
| Credential refresh | Manual | Automatic |
| Security | Good (read-only .env) | Lower (mounts home dir) |
| Container restarts | Required on refresh | Not required |
| Works with standard compose | ✅ Yes | ❌ No (needs sso compose) |
| Best for | Daily development | Quick testing |

## Quick Reference

```bash
# Check SSO login
aws sso login --profile PROFILE

# Export credentials (Option 1)
./scripts/sso-to-env.sh PROFILE
make down && make up

# Use mounted ~/.aws (Option 2)
export AWS_PROFILE=PROFILE
podman-compose -f podman-compose-sso.yml up -d

# Check credentials in container
podman exec agent-service printenv | grep AWS

# Test AWS connection
podman exec agent-service python3 -c "import boto3; print(boto3.client('sts').get_caller_identity())"

# View credential expiration
aws configure export-credentials --profile PROFILE --format json | jq -r '.Expiration'
```

## Getting Help

- **SSO not working?** Check [Troubleshooting](#troubleshooting) section
- **Container issues?** See [QUICKSTART.md](QUICKSTART.md)
- **Bedrock errors?** See [README.md](README.md)

## Summary

**For most users:** Use **Option 1** (Export to .env) with the `sso-to-env.sh` script. It's simple, secure, and works with the standard setup.

**For quick testing:** Use **Option 2** (Mount ~/.aws) if you don't mind restarting your SSO session occasionally.

Remember: SSO credentials are temporary. Keep your SSO session active and re-export credentials when they expire!
