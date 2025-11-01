# AWS SSO Quick Reference Card

## One-Line Commands

```bash
# With default profile
make up-sso

# With specific profile
make up-sso PROFILE=my-sso-profile

# Or use the automated script
./start-with-sso.sh my-sso-profile
```

## What `make up-sso` Does

1. ✅ Exports SSO credentials from AWS to `.env` file
2. ✅ Stops existing containers
3. ✅ Starts containers with fresh credentials
4. ✅ Shows service URLs and next steps

## Daily Workflow

### Morning (Start of Day)

```bash
# Login to SSO
aws sso login --profile your-profile

# Start everything
make up-sso PROFILE=your-profile

# Test it works
./test-agent.sh
```

### During the Day

```bash
# View logs
make logs

# Run tests
./test-agent.sh

# Check status
podman ps
```

### When Credentials Expire

You'll see errors like:
- "Unable to locate credentials"
- "ExpiredToken: The security token included in the request is expired"

**Solution:**
```bash
# Just re-run up-sso
make up-sso PROFILE=your-profile
```

### End of Day

```bash
# Stop services
make down
```

## All SSO-Related Commands

| Command | What It Does |
|---------|-------------|
| `make up-sso` | Export SSO credentials + start services (ONE COMMAND!) |
| `make sso-export` | Export SSO credentials to .env only |
| `make sso-up` | Start with mounted ~/.aws directory |
| `./start-with-sso.sh` | Fully automated setup script |
| `./scripts/sso-to-env.sh` | Export credentials (manual) |
| `./troubleshoot-credentials.sh` | Debug credential issues |

## Comparison of Methods

### Method 1: `make up-sso` ⭐ RECOMMENDED

```bash
make up-sso PROFILE=your-profile
```

**Best for:** Daily use, quick restarts
**Pros:** Simple, one command, automated
**Cons:** Need to re-run when credentials expire

### Method 2: `./start-with-sso.sh`

```bash
./start-with-sso.sh your-profile
```

**Best for:** First-time setup, troubleshooting
**Pros:** More verbose output, includes validation
**Cons:** Slightly slower (extra checks)

### Method 3: `make sso-up`

```bash
make sso-up PROFILE=your-profile
```

**Best for:** Long development sessions
**Pros:** Auto-refreshes from SSO session
**Cons:** Requires different compose file, mounts home directory

## Troubleshooting

### Check if you're logged in

```bash
aws sts get-caller-identity --profile your-profile
```

If error → login:
```bash
aws sso login --profile your-profile
```

### Check credentials in container

```bash
podman exec agent-service printenv | grep AWS
```

Should show all AWS variables with values (not empty).

### Check credential expiration

```bash
aws configure export-credentials --profile your-profile --format json | jq -r '.Expiration'
```

### Full troubleshooting

```bash
./troubleshoot-credentials.sh
```

## Profile Configuration

Your `~/.aws/config` should look like:

```ini
[profile your-profile]
sso_start_url = https://your-org.awsapps.com/start
sso_region = us-east-1
sso_account_id = 123456789012
sso_role_name = YourRoleName
region = us-east-1
```

## Common Scenarios

### Scenario 1: First time setup

```bash
# Configure SSO (one time)
aws configure sso --profile work

# Login and start
aws sso login --profile work
make up-sso PROFILE=work
```

### Scenario 2: Daily restart

```bash
make up-sso PROFILE=work
```

### Scenario 3: Credentials expired mid-session

```bash
# Just re-run
make up-sso PROFILE=work
```

### Scenario 4: Switching profiles

```bash
# Stop current
make down

# Start with different profile
make up-sso PROFILE=other-profile
```

### Scenario 5: Debugging issues

```bash
# Run troubleshooting
./troubleshoot-credentials.sh

# Check logs
make logs

# Rebuild if needed
make build
make up-sso PROFILE=your-profile
```

## Environment Variables Set

When you run `make up-sso`, these are set in `.env`:

```bash
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=ASIA... (temporary)
AWS_SECRET_ACCESS_KEY=... (temporary)
AWS_SESSION_TOKEN=... (temporary)
BEDROCK_MODEL_ID=anthropic.claude-3-5-sonnet-20241022-v2:0
MCP_FILESYSTEM_URL=http://mcp-filesystem:3001
MCP_CALCULATOR_URL=http://mcp-calculator:3002
```

## Tips & Best Practices

1. **Login at start of day**
   ```bash
   aws sso login --profile your-profile
   ```

2. **Use up-sso for everything**
   ```bash
   make up-sso PROFILE=your-profile
   ```

3. **Set default profile** in `~/.aws/config`:
   ```ini
   [default]
   sso_start_url = https://your-org.awsapps.com/start
   ...
   ```
   Then just use:
   ```bash
   make up-sso  # Uses default profile
   ```

4. **Create aliases** in `~/.bashrc`:
   ```bash
   alias work-start='make up-sso PROFILE=work'
   alias work-stop='make down'
   ```

5. **Monitor credential expiration** (optional):
   ```bash
   # Add to cron: check every hour and notify
   0 * * * * aws sts get-caller-identity --profile work &>/dev/null || notify-send "AWS SSO expired"
   ```

## Quick Command Cheat Sheet

```bash
# Start everything (most common)
make up-sso PROFILE=work

# Check status
podman ps

# View logs
make logs

# Test agent
./test-agent.sh

# Stop everything
make down

# Troubleshoot
./troubleshoot-credentials.sh

# Check expiration
aws configure export-credentials --profile work --format json | jq -r '.Expiration'
```

## Need Help?

- **SSO Setup:** See [AWS_SSO_SETUP.md](AWS_SSO_SETUP.md)
- **General Help:** See [QUICKSTART.md](QUICKSTART.md)
- **Detailed Docs:** See [README.md](README.md)

## Summary

**The simplest workflow:**

```bash
# Once per work session (or when credentials expire)
aws sso login --profile your-profile
make up-sso PROFILE=your-profile

# That's it! Now you can use the agent.
```
