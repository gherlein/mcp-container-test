#!/bin/bash

# EKS Deployment Script for Bedrock Agent
# This script helps automate the EKS deployment process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REGISTRY=""
AWS_ACCOUNT_ID=""
CLUSTER_NAME=""

echo "========================================="
echo "Bedrock Agent EKS Deployment Script"
echo "========================================="
echo ""

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    print_success "AWS CLI found"

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install it first."
        exit 1
    fi
    print_success "kubectl found"

    if ! command -v podman &> /dev/null; then
        print_error "Podman not found. Please install it first."
        exit 1
    fi
    print_success "Podman found"

    echo ""
}

# Get AWS account details
get_aws_details() {
    print_info "Getting AWS account details..."

    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Failed to get AWS account ID. Check your AWS credentials."
        exit 1
    fi

    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

    print_success "AWS Account ID: $AWS_ACCOUNT_ID"
    print_success "ECR Registry: $ECR_REGISTRY"
    echo ""
}

# Create ECR repositories
create_ecr_repos() {
    print_info "Creating ECR repositories..."

    repos=("agent-service" "mcp-filesystem" "mcp-calculator")

    for repo in "${repos[@]}"; do
        if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" &> /dev/null; then
            print_info "Repository $repo already exists"
        else
            aws ecr create-repository \
                --repository-name "$repo" \
                --region "$AWS_REGION" \
                --image-scanning-configuration scanOnPush=true \
                &> /dev/null
            print_success "Created repository: $repo"
        fi
    done

    echo ""
}

# Build and push images
build_and_push_images() {
    print_info "Building and pushing container images with Podman..."

    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | \
        podman login --username AWS --password-stdin "$ECR_REGISTRY"
    print_success "Logged into ECR"

    # Build and push agent-service
    print_info "Building agent-service..."
    podman build -t "$ECR_REGISTRY/agent-service:latest" ./agent-service
    podman push "$ECR_REGISTRY/agent-service:latest"
    print_success "Pushed agent-service"

    # Build and push mcp-filesystem
    print_info "Building mcp-filesystem..."
    podman build -t "$ECR_REGISTRY/mcp-filesystem:latest" ./mcp-servers/filesystem
    podman push "$ECR_REGISTRY/mcp-filesystem:latest"
    print_success "Pushed mcp-filesystem"

    # Build and push mcp-calculator
    print_info "Building mcp-calculator..."
    podman build -t "$ECR_REGISTRY/mcp-calculator:latest" ./mcp-servers/calculator
    podman push "$ECR_REGISTRY/mcp-calculator:latest"
    print_success "Pushed mcp-calculator"

    echo ""
}

# Update Kubernetes manifests
update_k8s_manifests() {
    print_info "Updating Kubernetes manifests..."

    # Create temporary directory for modified manifests
    mkdir -p /tmp/bedrock-agent-k8s
    cp -r k8s/* /tmp/bedrock-agent-k8s/

    # Update image references
    for file in /tmp/bedrock-agent-k8s/*-deployment.yaml; do
        sed -i.bak "s|YOUR_ECR_REGISTRY|$ECR_REGISTRY|g" "$file"
        rm "${file}.bak"
    done

    print_success "Updated image references"
    echo ""

    return 0
}

# Deploy to Kubernetes
deploy_to_k8s() {
    print_info "Deploying to Kubernetes..."

    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl is not configured. Please configure it to connect to your EKS cluster."
        exit 1
    fi

    CLUSTER_NAME=$(kubectl config current-context)
    print_success "Connected to cluster: $CLUSTER_NAME"

    # Apply manifests
    kubectl apply -f /tmp/bedrock-agent-k8s/namespace.yaml
    print_success "Created namespace"

    kubectl apply -f /tmp/bedrock-agent-k8s/configmap.yaml
    print_success "Created configmap"

    # Note: User needs to set up IRSA separately
    print_info "Applying serviceaccount (ensure IRSA is configured)..."
    kubectl apply -f /tmp/bedrock-agent-k8s/serviceaccount.yaml

    kubectl apply -f /tmp/bedrock-agent-k8s/mcp-filesystem-deployment.yaml
    kubectl apply -f /tmp/bedrock-agent-k8s/mcp-calculator-deployment.yaml
    kubectl apply -f /tmp/bedrock-agent-k8s/agent-deployment.yaml
    print_success "Created deployments"

    kubectl apply -f /tmp/bedrock-agent-k8s/hpa.yaml
    print_success "Created HPA"

    echo ""
    print_info "Waiting for deployments to be ready..."

    kubectl wait --for=condition=available --timeout=300s \
        deployment/mcp-filesystem \
        deployment/mcp-calculator \
        -n bedrock-agent

    print_success "MCP servers are ready"

    kubectl wait --for=condition=available --timeout=300s \
        deployment/agent-service \
        -n bedrock-agent

    print_success "Agent service is ready"

    echo ""
}

# Display deployment info
display_info() {
    echo "========================================="
    echo "Deployment Complete!"
    echo "========================================="
    echo ""

    echo "Resources in bedrock-agent namespace:"
    kubectl get all -n bedrock-agent

    echo ""
    echo "To get the agent service URL:"
    echo "  kubectl get svc -n bedrock-agent agent-service"
    echo ""
    echo "To view logs:"
    echo "  kubectl logs -n bedrock-agent -l app=agent-service -f"
    echo ""
    echo "To test the agent:"
    echo "  AGENT_URL=\$(kubectl get svc -n bedrock-agent agent-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
    echo "  ./test-agent.sh http://\$AGENT_URL"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    get_aws_details
    create_ecr_repos
    build_and_push_images
    update_k8s_manifests
    deploy_to_k8s
    display_info

    # Cleanup temp files
    rm -rf /tmp/bedrock-agent-k8s
}

# Run main function
main
