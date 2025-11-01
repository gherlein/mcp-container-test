# AWS Bedrock Cost Monitoring

Monitor your AWS Bedrock usage and costs with two complementary tools:

1. **`realtime-usage-monitor.py`** - Real-time usage (updated within 1-5 minutes)
2. **`cost-monitor.py`** - Historical costs (24-48 hour delay, but exact costs)

## Quick Start - Real-Time Usage ⚡

```bash
# See current usage and cost estimates (real-time)
python3 realtime-usage-monitor.py

# Last 6 hours
python3 realtime-usage-monitor.py --hours 6

# With AWS SSO
AWS_PROFILE=your-profile python3 realtime-usage-monitor.py
```

## Quick Start - Historical Costs 📊

### Option 1: Run with Python 3 (Easiest)

```bash
# Using system Python
python3 cost-monitor.py

# Or make it executable and run directly
./cost-monitor.py
```

### Option 2: Run in Agent Service Container

```bash
# If your containers are running
podman exec agent-service python3 /app/../cost-monitor.py
```

### Option 3: Run with AWS SSO Credentials

```bash
# Make sure you're logged in
aws sso login --profile your-profile

# Run with SSO profile
AWS_PROFILE=your-profile python3 cost-monitor.py
```

## Which Tool to Use?

| Feature | Real-Time Monitor | Cost Monitor |
|---------|------------------|--------------|
| **Data Source** | CloudWatch Metrics | Cost Explorer |
| **Latency** | 1-5 minutes | 24-48 hours |
| **Accuracy** | Estimates | Exact costs |
| **Token Counts** | ✅ Yes | ✅ Yes |
| **Actual Costs** | Estimated | ✅ Exact |
| **Usage Patterns** | ✅ Hourly | Daily |
| **Best For** | Development, debugging | Billing, reporting |

**Rule of Thumb:**
- **Use Real-Time Monitor** when developing/testing - see immediate feedback
- **Use Cost Monitor** for monthly billing and exact cost tracking

## Prerequisites

### For Real-Time Monitor

1. **AWS Credentials** with CloudWatch permissions
2. **Python 3** with boto3 installed
3. **No setup required** - CloudWatch metrics are automatic

### For Cost Monitor

1. **AWS Credentials** with Cost Explorer permissions
2. **Cost Explorer enabled** in your AWS account
3. **Python 3** with boto3 installed

### Required IAM Permissions

**For both tools:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "ce:GetCostAndUsage",
        "ce:GetCostForecast"
      ],
      "Resource": "*"
    }
  ]
}
```

**Minimal permissions:**
- Real-Time Monitor: `cloudwatch:GetMetricStatistics`
- Cost Monitor: `ce:GetCostAndUsage`

## Real-Time Usage Monitor

### Basic Usage

```bash
# Show usage for last 24 hours (default)
python3 realtime-usage-monitor.py

# Last 6 hours
python3 realtime-usage-monitor.py --hours 6

# Last hour
python3 realtime-usage-monitor.py --hours 1

# Different region
python3 realtime-usage-monitor.py --region us-west-2

# With AWS SSO
AWS_PROFILE=your-profile python3 realtime-usage-monitor.py
```

### Example Output

```
Fetching Bedrock metrics from 2025-10-31 13:00 to 2025-11-01 13:00 UTC...

======================================================================
AWS BEDROCK REAL-TIME USAGE SUMMARY
======================================================================

Total API Calls:     156
Total Input Tokens:  45,230
Total Output Tokens: 12,340

Average Latency:     2,145 ms
Max Latency:         5,234 ms

Estimated Cost (Claude 3.5 Sonnet v2 pricing):
----------------------------------------------------------------------
  Input Cost:        $0.1357 (45,230 tokens @ $3.00/1M)
  Output Cost:       $0.1851 (12,340 tokens @ $15.00/1M)
  Total Estimated:   $0.3208

Per API Call Averages:
----------------------------------------------------------------------
  Avg Input Tokens:  290
  Avg Output Tokens: 79
  Avg Cost:          $0.002056

Hourly Breakdown (Last 10 Hours):
----------------------------------------------------------------------
Time (UTC)           Calls   Input Tokens   Output Tokens
----------------------------------------------------------------------
2025-11-01 12:00        12          3,456          1,234
2025-11-01 11:00        23          6,789          2,345
...

Projected Costs (based on current usage rate):
----------------------------------------------------------------------
  Per Hour:          $0.0134
  Per Day (24h):     $0.32
  Per Month (30d):   $9.61

======================================================================
```

### What It Shows

1. **Immediate Feedback** - See usage within 1-5 minutes of API calls
2. **Token Counts** - Exact input/output token usage
3. **Cost Estimates** - Real-time cost projections
4. **Performance Metrics** - Latency and error rates
5. **Hourly Breakdown** - Usage patterns by hour
6. **Projections** - Estimated daily/monthly costs

## Historical Cost Monitor

### Basic Usage

```bash
# Show costs for last 30 days (default)
python3 cost-monitor.py
```

### Custom Time Range

```bash
# Show costs for last 7 days
python3 cost-monitor.py --days 7

# Show costs for last 90 days
python3 cost-monitor.py --days 90
```

### Export to JSON

```bash
# Export cost data to JSON file
python3 cost-monitor.py --json

# Custom output filename
python3 cost-monitor.py --json --output my-costs.json
```

### Specify Region

```bash
# Use different region
python3 cost-monitor.py --region us-west-2
```

### Combined Options

```bash
# Last 14 days, export to JSON
python3 cost-monitor.py --days 14 --json --output last-2-weeks.json
```

## Example Output

```
Fetching Bedrock costs from 2025-10-01 to 2025-11-01...

======================================================================
AWS BEDROCK COST SUMMARY
======================================================================

Total Cost: $24.56

Daily Breakdown:
----------------------------------------------------------------------
Date         Cost
----------------------------------------------------------------------
2025-10-31   $  1.23
2025-10-30   $  2.45
2025-10-29   $  0.89
2025-10-28   $  1.67
2025-10-27   $  3.21
2025-10-26   $  0.45
2025-10-25   $  2.11
2025-10-24   $  1.88
2025-10-23   $  0.92
2025-10-22   $  1.34
... and 21 more days

By Usage Type:
----------------------------------------------------------------------
Usage Type                                         Cost    Units
----------------------------------------------------------------------
USE1-Bedrock-Claude-3.5-Sonnet-Input               $ 15.23   5080000
USE1-Bedrock-Claude-3.5-Sonnet-Output              $  9.33    622000

Average Daily Cost: $0.82

Projected Monthly Cost (30 days): $24.60

======================================================================
```

## What the Script Shows

1. **Total Cost** - Overall Bedrock spending for the period
2. **Daily Breakdown** - Cost per day (last 10 days shown)
3. **Usage Type Breakdown** - Costs by input/output tokens, model used
4. **Average Daily Cost** - Average spending per day
5. **Projected Monthly Cost** - Estimated monthly cost based on average

## Understanding the Output

### Usage Types

Common usage type formats:
- `USE1-Bedrock-Claude-3.5-Sonnet-Input` - Input tokens to Claude 3.5 Sonnet in us-east-1
- `USE1-Bedrock-Claude-3.5-Sonnet-Output` - Output tokens from Claude 3.5 Sonnet
- `USW2-` prefix - us-west-2 region
- `EU-` prefix - European regions

### Cost Delay

**Important:** AWS Cost Explorer data typically has a **24-48 hour delay**.

If you don't see costs:
- Data may not be processed yet
- No API calls were made in the time period
- Cost Explorer might not be enabled

## Troubleshooting

### "No cost data available"

**Possible causes:**
1. Cost Explorer not enabled in your AWS account
   - Go to AWS Console → Billing → Cost Explorer
   - Click "Enable Cost Explorer"
2. No Bedrock usage yet
3. Data delay (24-48 hours)

### "Access Denied" error

**Solution:**
- Add `ce:GetCostAndUsage` permission to your IAM user/role
- See "Required IAM Permissions" above

### "Unable to locate credentials"

**Solution:**

**If using AWS SSO:**
```bash
# Login first
aws sso login --profile your-profile

# Run with profile
AWS_PROFILE=your-profile python3 cost-monitor.py
```

**If using static credentials:**
```bash
# Make sure .env file exists
cat .env

# Export credentials
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_REGION=us-east-1

# Run script
python3 cost-monitor.py
```

### boto3 not installed

**Solution:**
```bash
# Install boto3
pip3 install boto3

# Or use system package manager
# Ubuntu/Debian:
sudo apt-get install python3-boto3

# macOS:
brew install boto3

# Or run in container (has boto3)
podman exec agent-service python3 /workspace/cost-monitor.py
```

## Running in Different Environments

### Local (Your Machine)

```bash
# Ensure boto3 is installed
pip3 install boto3

# Run script
python3 cost-monitor.py
```

### In Agent Service Container

```bash
# Make sure containers are running
make up

# Run in container (boto3 already installed)
podman exec agent-service python3 /workspace/cost-monitor.py
```

### On Schedule (Cron)

Monitor costs daily:

```bash
# Edit crontab
crontab -e

# Add daily cost check at 9 AM
0 9 * * * cd /path/to/project && python3 cost-monitor.py > /tmp/bedrock-costs-$(date +\%Y\%m\%d).log 2>&1
```

### In CI/CD Pipeline

```yaml
# GitHub Actions example
- name: Check Bedrock Costs
  run: |
    python3 cost-monitor.py --days 7
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    AWS_REGION: us-east-1
```

## Understanding Bedrock Costs

### Pricing Model

Bedrock charges based on:
1. **Input tokens** - Text sent to the model
2. **Output tokens** - Text generated by the model

### Current Pricing (as of 2025)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Claude 3.5 Sonnet v2 | $3.00 | $15.00 |
| Claude 3.5 Sonnet v1 | $3.00 | $15.00 |
| Claude 3 Opus | $15.00 | $75.00 |
| Claude 3 Sonnet | $3.00 | $15.00 |
| Claude 3 Haiku | $0.25 | $1.25 |

Check [AWS Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/) for current rates.

### Cost Optimization Tips

1. **Use shorter prompts** - Less input tokens = lower cost
2. **Limit output length** - Use `max_tokens` parameter
3. **Cache prompts** - Reuse common prompts (if supported)
4. **Use Haiku for simple tasks** - Much cheaper than Sonnet/Opus
5. **Monitor daily** - Catch unexpected usage early
6. **Set billing alarms** - AWS Budgets can alert on spending

## Setting Up Cost Alerts

### AWS Budgets

1. Go to AWS Console → Billing → Budgets
2. Create Budget
3. Choose "Cost budget"
4. Set monthly amount (e.g., $50)
5. Configure alerts at 80%, 100%, 120%

### CloudWatch Alarms

Create alarms for Bedrock API calls:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name bedrock-high-usage \
  --alarm-description "Alert on high Bedrock usage" \
  --metric-name InvokeModel \
  --namespace AWS/Bedrock \
  --statistic Sum \
  --period 3600 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold
```

## Exporting Cost Data

### JSON Format

```bash
# Export to JSON
python3 cost-monitor.py --json

# Use jq to analyze
cat bedrock-costs.json | jq '.ResultsByTime[] | {date: .TimePeriod.Start, cost: .Total.UnblendedCost.Amount}'
```

### CSV Format

```bash
# Convert JSON to CSV
python3 cost-monitor.py --json
cat bedrock-costs.json | jq -r '.ResultsByTime[] | [.TimePeriod.Start, .Total.UnblendedCost.Amount] | @csv' > costs.csv
```

## Integration with Project

### Add to Makefile

Add cost monitoring to your Makefile:

```makefile
cost:
	@echo "Checking Bedrock costs..."
	python3 cost-monitor.py

cost-json:
	python3 cost-monitor.py --json --output costs-$(shell date +%Y%m%d).json
```

Usage:
```bash
make cost       # Show costs
make cost-json  # Export to dated JSON file
```

### Monitor in Container

```bash
# Check costs from within running agent
podman exec agent-service python3 /workspace/cost-monitor.py --days 7
```

## Advanced Usage

### Programmatic Access

Use the script as a module:

```python
from cost_monitor import get_bedrock_costs

# Get cost data
response = get_bedrock_costs(days=30)

# Process data
# ... your custom analysis ...
```

### Custom Filtering

Modify the script to filter by:
- Specific models
- Specific regions
- Specific time periods
- Usage patterns

## Resources

- [AWS Cost Explorer Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html)
- [AWS Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
- [boto3 Cost Explorer Client](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ce.html)

## Summary

**Quick Commands:**
```bash
# Basic check
python3 cost-monitor.py

# Last week
python3 cost-monitor.py --days 7

# Export to JSON
python3 cost-monitor.py --json

# With AWS SSO
AWS_PROFILE=work python3 cost-monitor.py
```

**Remember:**
- Cost data has 24-48 hour delay
- Requires Cost Explorer permissions
- Input tokens + output tokens = total cost
- Monitor regularly to avoid surprises!
