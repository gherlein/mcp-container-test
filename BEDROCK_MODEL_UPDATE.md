# AWS Bedrock Model ID Update

## What Changed

AWS Bedrock recently changed how model invocations work. You now need to use **inference profile IDs** instead of direct model IDs.

### Old Format (No Longer Works)
```
anthropic.claude-3-5-sonnet-20241022-v2:0
```

### New Format (Required)
```
us.anthropic.claude-3-5-sonnet-20241022-v2:0
```

## Error You Might See

```
Invocation of model ID anthropic.claude-3-5-sonnet-20241022-v2:0 with on-demand
throughput isn't supported. Retry your request with the ID or ARN of an inference
profile that contains this model.
```

## Quick Fix

### Step 1: Update Your .env File

Edit your `.env` file and change the `BEDROCK_MODEL_ID`:

```bash
# OLD (remove this)
BEDROCK_MODEL_ID=anthropic.claude-3-5-sonnet-20241022-v2:0

# NEW (use this)
BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0
```

### Step 2: Restart Containers

```bash
make down
make up

# Or if using SSO
make up-sso PROFILE=your-profile
```

### Step 3: Test

```bash
./test-agent.sh
```

## Available Inference Profile IDs

### Claude 3.5 Sonnet v2 (Recommended)

```bash
# Cross-region US (recommended)
BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0

# Cross-region EU
BEDROCK_MODEL_ID=eu.anthropic.claude-3-5-sonnet-20241022-v2:0

# Region-specific (replace {region} with your region)
BEDROCK_MODEL_ID=us-east-1.anthropic.claude-3-5-sonnet-20241022-v2:0
BEDROCK_MODEL_ID=us-west-2.anthropic.claude-3-5-sonnet-20241022-v2:0
```

### Other Claude Models

```bash
# Claude 3.5 Sonnet v1
BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20240620-v1:0

# Claude 3 Opus
BEDROCK_MODEL_ID=us.anthropic.claude-3-opus-20240229-v1:0

# Claude 3 Sonnet
BEDROCK_MODEL_ID=us.anthropic.claude-3-sonnet-20240229-v1:0

# Claude 3 Haiku
BEDROCK_MODEL_ID=us.anthropic.claude-3-haiku-20240307-v1:0
```

## Understanding Inference Profiles

### Cross-Region Profiles (Recommended)

Format: `{region-group}.{provider}.{model-name}:{version}`

Example: `us.anthropic.claude-3-5-sonnet-20241022-v2:0`

**Benefits:**
- ✅ Automatic failover across multiple AWS regions
- ✅ Higher availability
- ✅ Better throughput
- ✅ Simpler configuration (don't need to specify exact region)

**Use this for:** Production workloads, high-availability applications

### Region-Specific Profiles

Format: `{region}.{provider}.{model-name}:{version}`

Example: `us-east-1.anthropic.claude-3-5-sonnet-20241022-v2:0`

**Benefits:**
- ✅ Guaranteed to stay in specific region (compliance requirements)
- ✅ Predictable latency

**Use this for:** Data sovereignty requirements, specific compliance needs

## How to Choose

### For Most Users (Recommended)

Use **cross-region US** profile:
```bash
BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0
```

### For EU Users

Use **cross-region EU** profile:
```bash
BEDROCK_MODEL_ID=eu.anthropic.claude-3-5-sonnet-20241022-v2:0
```

### For Compliance Requirements

Use **region-specific** profile:
```bash
# Must stay in us-east-1
BEDROCK_MODEL_ID=us-east-1.anthropic.claude-3-5-sonnet-20241022-v2:0
```

## Checking Available Models

### List All Available Models

```bash
# List foundation models
aws bedrock list-foundation-models --region us-east-1

# Filter for Claude models
aws bedrock list-foundation-models \
  --region us-east-1 \
  --by-provider anthropic \
  --query 'modelSummaries[*].[modelId,modelName]' \
  --output table
```

### List Inference Profiles

```bash
# List all inference profiles
aws bedrock list-inference-profiles --region us-east-1

# Get details about a specific profile
aws bedrock get-inference-profile \
  --inference-profile-identifier "us.anthropic.claude-3-5-sonnet-20241022-v2:0" \
  --region us-east-1
```

## Testing Different Models

You can easily switch models by updating your `.env` file:

```bash
# Edit .env
nano .env

# Change BEDROCK_MODEL_ID to desired model
# For example:
BEDROCK_MODEL_ID=us.anthropic.claude-3-opus-20240229-v1:0

# Restart
make down && make up

# Test
./test-agent.sh
```

## Troubleshooting

### Error: "Could not resolve the foundation model"

**Cause:** Model not available in your region

**Solution:**
1. Check which regions support the model:
   ```bash
   aws bedrock list-foundation-models \
     --by-provider anthropic \
     --region us-east-1
   ```

2. Try a different region or cross-region profile

### Error: "AccessDeniedException"

**Cause:** Model access not enabled in your AWS account

**Solution:**
1. Go to AWS Console → Bedrock → Model access
2. Enable access for Claude models
3. Wait for approval (usually instant for Claude)

### Error: "ValidationException: Invalid model identifier"

**Cause:** Typo in model ID or using old format

**Solution:**
- Verify you're using the new inference profile format
- Check for typos in the model ID
- Ensure you're using a supported model ID

### How to Verify Your Current Model ID

```bash
# Check what's in your .env file
grep BEDROCK_MODEL_ID .env

# Check what the container sees
podman exec agent-service printenv BEDROCK_MODEL_ID

# Test the model ID
aws bedrock get-inference-profile \
  --inference-profile-identifier "$(grep BEDROCK_MODEL_ID .env | cut -d= -f2)" \
  --region us-east-1
```

## Cost Implications

Different models have different costs:

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Claude 3.5 Sonnet v2 | $3.00 | $15.00 |
| Claude 3.5 Sonnet v1 | $3.00 | $15.00 |
| Claude 3 Opus | $15.00 | $75.00 |
| Claude 3 Sonnet | $3.00 | $15.00 |
| Claude 3 Haiku | $0.25 | $1.25 |

*Prices as of early 2025, check AWS pricing for current rates*

## Migration Checklist

- [ ] Update `.env` file with new model ID
- [ ] Update `.env.example` if you've customized it
- [ ] Restart containers: `make down && make up`
- [ ] Test agent: `./test-agent.sh`
- [ ] Update any CI/CD pipelines with new model ID
- [ ] Update Kubernetes ConfigMaps (for EKS deployments)
- [ ] Document which model ID you're using in your team docs

## Additional Resources

- [AWS Bedrock Inference Profiles Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html)
- [AWS Bedrock Model IDs](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html)
- [Anthropic Model Documentation](https://docs.anthropic.com/claude/docs/models-overview)

## Summary

**Quick fix for the error:**

```bash
# 1. Edit .env file
nano .env

# 2. Change this line:
BEDROCK_MODEL_ID=us.anthropic.claude-3-5-sonnet-20241022-v2:0

# 3. Restart
make down && make up

# 4. Test
./test-agent.sh
```

That's it! The agent should now work properly.
