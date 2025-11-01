#!/usr/bin/env python3
"""
AWS Bedrock Real-Time Usage Monitor

This script uses CloudWatch Metrics to show real-time Bedrock usage.
Unlike Cost Explorer (24-48 hour delay), CloudWatch metrics are available immediately.
"""

import boto3
import sys
from datetime import datetime, timedelta
from decimal import Decimal

# Claude 3.5 Sonnet v2 pricing (per 1M tokens)
PRICING = {
    'claude-3-5-sonnet-20241022-v2:0': {
        'input': Decimal('3.00'),
        'output': Decimal('15.00')
    },
    'claude-3-5-sonnet-20240620-v1:0': {
        'input': Decimal('3.00'),
        'output': Decimal('15.00')
    },
    'claude-3-opus-20240229-v1:0': {
        'input': Decimal('15.00'),
        'output': Decimal('75.00')
    },
    'claude-3-sonnet-20240229-v1:0': {
        'input': Decimal('3.00'),
        'output': Decimal('15.00')
    },
    'claude-3-haiku-20240307-v1:0': {
        'input': Decimal('0.25'),
        'output': Decimal('1.25')
    }
}

def get_bedrock_metrics(hours=24, region='us-east-1'):
    """
    Get Bedrock CloudWatch metrics for the specified time period

    Args:
        hours: Number of hours to look back (default: 24)
        region: AWS region (default: us-east-1)

    Returns:
        dict: Metrics data from CloudWatch
    """
    try:
        cw = boto3.client('cloudwatch', region_name=region)

        # Calculate time range
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)

        print(f"Fetching Bedrock metrics from {start_time.strftime('%Y-%m-%d %H:%M')} to {end_time.strftime('%Y-%m-%d %H:%M')} UTC...")
        print()

        metrics = {}

        # Get invocation count
        print("Querying invocation count...")
        response = cw.get_metric_statistics(
            Namespace='AWS/Bedrock',
            MetricName='Invocations',
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,  # 1 hour periods
            Statistics=['Sum'],
            Dimensions=[]
        )
        metrics['invocations'] = response.get('Datapoints', [])

        # Get input tokens
        print("Querying input tokens...")
        response = cw.get_metric_statistics(
            Namespace='AWS/Bedrock',
            MetricName='InputTokens',
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Sum'],
            Dimensions=[]
        )
        metrics['input_tokens'] = response.get('Datapoints', [])

        # Get output tokens
        print("Querying output tokens...")
        response = cw.get_metric_statistics(
            Namespace='AWS/Bedrock',
            MetricName='OutputTokens',
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Sum'],
            Dimensions=[]
        )
        metrics['output_tokens'] = response.get('Datapoints', [])

        # Get invocation latency
        print("Querying invocation latency...")
        response = cw.get_metric_statistics(
            Namespace='AWS/Bedrock',
            MetricName='InvocationLatency',
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Average', 'Maximum'],
            Dimensions=[]
        )
        metrics['latency'] = response.get('Datapoints', [])

        # Get errors
        print("Querying errors...")
        response = cw.get_metric_statistics(
            Namespace='AWS/Bedrock',
            MetricName='InvocationClientErrors',
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Sum'],
            Dimensions=[]
        )
        metrics['client_errors'] = response.get('Datapoints', [])

        response = cw.get_metric_statistics(
            Namespace='AWS/Bedrock',
            MetricName='InvocationServerErrors',
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Sum'],
            Dimensions=[]
        )
        metrics['server_errors'] = response.get('Datapoints', [])

        print()
        return metrics

    except Exception as e:
        print(f"Error fetching CloudWatch metrics: {e}", file=sys.stderr)
        print("\nMake sure you have:", file=sys.stderr)
        print("  1. AWS credentials configured", file=sys.stderr)
        print("  2. Permission: cloudwatch:GetMetricStatistics", file=sys.stderr)
        print("  3. Bedrock usage in the specified time period", file=sys.stderr)
        return None

def estimate_cost(input_tokens, output_tokens, model_id=None):
    """
    Estimate cost based on token usage

    Args:
        input_tokens: Number of input tokens
        output_tokens: Number of output tokens
        model_id: Model ID (if known)

    Returns:
        Decimal: Estimated cost in dollars
    """
    # Use Claude 3.5 Sonnet v2 pricing as default
    if model_id and model_id in PRICING:
        pricing = PRICING[model_id]
    else:
        pricing = PRICING['claude-3-5-sonnet-20241022-v2:0']

    input_cost = (Decimal(str(input_tokens)) / Decimal('1000000')) * pricing['input']
    output_cost = (Decimal(str(output_tokens)) / Decimal('1000000')) * pricing['output']

    return input_cost + output_cost

def print_usage_summary(metrics):
    """Print a formatted summary of usage metrics"""
    if not metrics:
        print("No metrics data available")
        return

    # Aggregate totals
    total_invocations = sum(dp['Sum'] for dp in metrics.get('invocations', []))
    total_input_tokens = sum(dp['Sum'] for dp in metrics.get('input_tokens', []))
    total_output_tokens = sum(dp['Sum'] for dp in metrics.get('output_tokens', []))
    total_client_errors = sum(dp['Sum'] for dp in metrics.get('client_errors', []))
    total_server_errors = sum(dp['Sum'] for dp in metrics.get('server_errors', []))

    # Calculate latency stats
    latency_datapoints = metrics.get('latency', [])
    if latency_datapoints:
        avg_latency = sum(dp['Average'] for dp in latency_datapoints) / len(latency_datapoints)
        max_latency = max(dp['Maximum'] for dp in latency_datapoints)
    else:
        avg_latency = 0
        max_latency = 0

    # Print summary
    print("=" * 70)
    print("AWS BEDROCK REAL-TIME USAGE SUMMARY")
    print("=" * 70)
    print()

    if total_invocations == 0:
        print("No Bedrock API calls detected in this period.")
        print()
        print("This could mean:")
        print("  - No API calls were made")
        print("  - CloudWatch metrics haven't propagated yet (usually 1-5 minutes)")
        print("  - You're looking at the wrong region")
        print()
        print("Tip: Try running your agent and then check again in a few minutes.")
        return

    # Usage stats
    print(f"Total API Calls:     {total_invocations:,.0f}")
    print(f"Total Input Tokens:  {total_input_tokens:,.0f}")
    print(f"Total Output Tokens: {total_output_tokens:,.0f}")
    print()

    # Error stats
    total_errors = total_client_errors + total_server_errors
    if total_errors > 0:
        error_rate = (total_errors / total_invocations) * 100
        print(f"Errors:              {total_errors:,.0f} ({error_rate:.2f}%)")
        print(f"  Client Errors:     {total_client_errors:,.0f}")
        print(f"  Server Errors:     {total_server_errors:,.0f}")
        print()

    # Performance stats
    if avg_latency > 0:
        print(f"Average Latency:     {avg_latency:,.0f} ms")
        print(f"Max Latency:         {max_latency:,.0f} ms")
        print()

    # Cost estimation
    print("Estimated Cost (Claude 3.5 Sonnet v2 pricing):")
    print("-" * 70)

    estimated_cost = estimate_cost(total_input_tokens, total_output_tokens)
    input_cost = estimate_cost(total_input_tokens, 0)
    output_cost = estimate_cost(0, total_output_tokens)

    print(f"  Input Cost:        ${input_cost:.4f} ({total_input_tokens:,.0f} tokens @ $3.00/1M)")
    print(f"  Output Cost:       ${output_cost:.4f} ({total_output_tokens:,.0f} tokens @ $15.00/1M)")
    print(f"  Total Estimated:   ${estimated_cost:.4f}")
    print()

    # Averages
    if total_invocations > 0:
        avg_input = total_input_tokens / total_invocations
        avg_output = total_output_tokens / total_invocations
        avg_cost_per_call = estimated_cost / Decimal(str(total_invocations))

        print("Per API Call Averages:")
        print("-" * 70)
        print(f"  Avg Input Tokens:  {avg_input:,.0f}")
        print(f"  Avg Output Tokens: {avg_output:,.0f}")
        print(f"  Avg Cost:          ${avg_cost_per_call:.6f}")
        print()

    # Hourly breakdown (if we have data)
    invocation_datapoints = sorted(metrics.get('invocations', []),
                                   key=lambda x: x['Timestamp'],
                                   reverse=True)

    if len(invocation_datapoints) > 1:
        print("Hourly Breakdown (Last 10 Hours):")
        print("-" * 70)
        print(f"{'Time (UTC)':<20} {'Calls':>10} {'Input Tokens':>15} {'Output Tokens':>16}")
        print("-" * 70)

        # Get corresponding token data
        input_by_time = {dp['Timestamp']: dp['Sum'] for dp in metrics.get('input_tokens', [])}
        output_by_time = {dp['Timestamp']: dp['Sum'] for dp in metrics.get('output_tokens', [])}

        for dp in invocation_datapoints[:10]:
            timestamp = dp['Timestamp'].strftime('%Y-%m-%d %H:%M')
            calls = dp['Sum']
            input_tokens = input_by_time.get(dp['Timestamp'], 0)
            output_tokens = output_by_time.get(dp['Timestamp'], 0)

            print(f"{timestamp:<20} {calls:>10,.0f} {input_tokens:>15,.0f} {output_tokens:>16,.0f}")

        if len(invocation_datapoints) > 10:
            print(f"... and {len(invocation_datapoints) - 10} more hours")
        print()

    # Projected costs
    if total_invocations > 0 and len(invocation_datapoints) > 0:
        hours_of_data = len(invocation_datapoints)
        hourly_rate = estimated_cost / Decimal(str(hours_of_data))
        daily_projection = hourly_rate * 24
        monthly_projection = daily_projection * 30

        print("Projected Costs (based on current usage rate):")
        print("-" * 70)
        print(f"  Per Hour:          ${hourly_rate:.4f}")
        print(f"  Per Day (24h):     ${daily_projection:.2f}")
        print(f"  Per Month (30d):   ${monthly_projection:.2f}")
        print()

    print("=" * 70)
    print()
    print("Note: These are estimates based on CloudWatch metrics and may not")
    print("reflect exact costs. Actual costs will appear in Cost Explorer in 24-48 hours.")
    print()
    print("Pricing assumes Claude 3.5 Sonnet v2. Actual costs may vary by model.")

def main():
    """Main function"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Monitor AWS Bedrock real-time usage via CloudWatch Metrics'
    )
    parser.add_argument(
        '-H', '--hours',
        type=int,
        default=24,
        help='Number of hours to look back (default: 24)'
    )
    parser.add_argument(
        '-r', '--region',
        default='us-east-1',
        help='AWS region (default: us-east-1)'
    )

    args = parser.parse_args()

    # Get metrics
    metrics = get_bedrock_metrics(hours=args.hours, region=args.region)

    if metrics:
        # Print summary
        print_usage_summary(metrics)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
