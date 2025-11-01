#!/usr/bin/env python3
"""
AWS Bedrock Cost Monitor

This script uses the AWS Cost Explorer API to monitor Bedrock usage and costs.
Requires AWS credentials with ce:GetCostAndUsage permissions.
"""

import boto3
import json
import sys
from datetime import datetime, timedelta
from decimal import Decimal

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def get_bedrock_costs(days=30, region='us-east-1'):
    """
    Get Bedrock costs for the specified number of days

    Args:
        days: Number of days to look back (default: 30)
        region: AWS region (default: us-east-1)

    Returns:
        dict: Cost data from Cost Explorer
    """
    try:
        ce = boto3.client('ce', region_name=region)

        # Calculate date range
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=days)

        print(f"Fetching Bedrock costs from {start_date} to {end_date}...")
        print()

        response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['UnblendedCost', 'UsageQuantity'],
            Filter={
                'Dimensions': {
                    'Key': 'SERVICE',
                    'Values': ['Amazon Bedrock']
                }
            },
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'USAGE_TYPE'
                }
            ]
        )

        return response

    except Exception as e:
        print(f"Error fetching cost data: {e}", file=sys.stderr)
        print("\nMake sure you have:", file=sys.stderr)
        print("  1. AWS credentials configured", file=sys.stderr)
        print("  2. Permission: ce:GetCostAndUsage", file=sys.stderr)
        print("  3. Cost Explorer enabled in your AWS account", file=sys.stderr)
        return None

def print_cost_summary(response):
    """Print a formatted summary of costs"""
    if not response or 'ResultsByTime' not in response:
        print("No cost data available")
        return

    total_cost = Decimal('0')
    daily_costs = []
    usage_types = {}

    # Process results
    for result in response['ResultsByTime']:
        date = result['TimePeriod']['Start']

        if result.get('Groups'):
            day_cost = Decimal('0')
            for group in result['Groups']:
                usage_type = group['Keys'][0]
                cost = Decimal(group['Metrics']['UnblendedCost']['Amount'])
                usage = Decimal(group['Metrics']['UsageQuantity']['Amount'])

                day_cost += cost

                # Track usage types
                if usage_type not in usage_types:
                    usage_types[usage_type] = {'cost': Decimal('0'), 'usage': Decimal('0')}
                usage_types[usage_type]['cost'] += cost
                usage_types[usage_type]['usage'] += usage

            if day_cost > 0:
                daily_costs.append({'date': date, 'cost': day_cost})
                total_cost += day_cost
        elif result.get('Total'):
            cost = Decimal(result['Total']['UnblendedCost']['Amount'])
            if cost > 0:
                daily_costs.append({'date': date, 'cost': cost})
                total_cost += cost

    # Print summary
    print("=" * 70)
    print("AWS BEDROCK COST SUMMARY")
    print("=" * 70)
    print()

    if total_cost == 0:
        print("No Bedrock usage detected in this period.")
        print("This could mean:")
        print("  - No API calls were made")
        print("  - Costs haven't been processed yet (usually 24-48 hour delay)")
        print("  - Cost Explorer data is not available for this period")
        return

    print(f"Total Cost: ${total_cost:.2f}")
    print()

    # Print daily breakdown
    if daily_costs:
        print("Daily Breakdown:")
        print("-" * 70)
        print(f"{'Date':<12} {'Cost':>10}")
        print("-" * 70)

        for day in sorted(daily_costs, key=lambda x: x['date'], reverse=True)[:10]:
            print(f"{day['date']:<12} ${day['cost']:>9.2f}")

        if len(daily_costs) > 10:
            print(f"... and {len(daily_costs) - 10} more days")
        print()

    # Print usage type breakdown
    if usage_types:
        print("By Usage Type:")
        print("-" * 70)
        print(f"{'Usage Type':<50} {'Cost':>10} {'Units':>8}")
        print("-" * 70)

        for usage_type, data in sorted(usage_types.items(),
                                       key=lambda x: x[1]['cost'],
                                       reverse=True):
            # Shorten usage type name for display
            display_name = usage_type[:47] + "..." if len(usage_type) > 50 else usage_type
            print(f"{display_name:<50} ${data['cost']:>9.2f} {data['usage']:>8.0f}")
        print()

    # Print average daily cost
    if daily_costs:
        avg_daily = total_cost / len(daily_costs)
        print(f"Average Daily Cost: ${avg_daily:.2f}")
        print()

    # Print projected monthly cost
    if daily_costs:
        projected_monthly = avg_daily * 30
        print(f"Projected Monthly Cost (30 days): ${projected_monthly:.2f}")
        print()

    print("=" * 70)

def export_json(response, filename='bedrock-costs.json'):
    """Export cost data to JSON file"""
    try:
        with open(filename, 'w') as f:
            json.dump(response, f, default=decimal_default, indent=2)
        print(f"\nCost data exported to: {filename}")
    except Exception as e:
        print(f"Error exporting to JSON: {e}", file=sys.stderr)

def main():
    """Main function"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Monitor AWS Bedrock costs using Cost Explorer API'
    )
    parser.add_argument(
        '-d', '--days',
        type=int,
        default=30,
        help='Number of days to look back (default: 30)'
    )
    parser.add_argument(
        '-r', '--region',
        default='us-east-1',
        help='AWS region (default: us-east-1)'
    )
    parser.add_argument(
        '-j', '--json',
        action='store_true',
        help='Export to JSON file'
    )
    parser.add_argument(
        '-o', '--output',
        default='bedrock-costs.json',
        help='JSON output filename (default: bedrock-costs.json)'
    )

    args = parser.parse_args()

    # Get cost data
    response = get_bedrock_costs(days=args.days, region=args.region)

    if response:
        # Print summary
        print_cost_summary(response)

        # Export to JSON if requested
        if args.json:
            export_json(response, args.output)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
