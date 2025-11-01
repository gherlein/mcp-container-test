#!/bin/bash

# EKS Cleanup Script for Bedrock Agent

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "========================================="
echo "Bedrock Agent EKS Cleanup Script"
echo "========================================="
echo ""

print_warning "This will delete all Bedrock Agent resources from Kubernetes."
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""

# Delete Kubernetes resources
if kubectl get namespace bedrock-agent &> /dev/null; then
    print_warning "Deleting Kubernetes resources..."

    kubectl delete -f k8s/hpa.yaml 2>/dev/null || true
    kubectl delete -f k8s/agent-deployment.yaml 2>/dev/null || true
    kubectl delete -f k8s/mcp-calculator-deployment.yaml 2>/dev/null || true
    kubectl delete -f k8s/mcp-filesystem-deployment.yaml 2>/dev/null || true
    kubectl delete -f k8s/configmap.yaml 2>/dev/null || true
    kubectl delete -f k8s/serviceaccount.yaml 2>/dev/null || true
    kubectl delete -f k8s/namespace.yaml 2>/dev/null || true

    print_success "Deleted Kubernetes resources"
else
    print_warning "Namespace bedrock-agent not found, skipping K8s cleanup"
fi

echo ""
print_warning "ECR repositories are NOT deleted by this script."
echo "To delete ECR repositories and images, run:"
echo "  aws ecr delete-repository --repository-name agent-service --force"
echo "  aws ecr delete-repository --repository-name mcp-filesystem --force"
echo "  aws ecr delete-repository --repository-name mcp-calculator --force"
echo ""

print_success "Cleanup complete!"
