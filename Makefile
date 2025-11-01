.PHONY: help build up down logs test clean deploy-k8s delete-k8s push-images pod-create pod-start pod-stop pod-remove sso-export sso-up up-sso

# Use podman compose or podman-compose depending on installation
PODMAN_COMPOSE := $(shell command -v podman-compose 2>/dev/null || echo "podman compose")

# AWS SSO Profile (override with: make up-sso PROFILE=your-profile)
PROFILE ?= default

help:
	@echo "Available commands:"
	@echo "  make build         - Build all Podman images"
	@echo "  make up            - Start all services with Podman Compose"
	@echo "  make up-sso        - Export SSO credentials and start services (PROFILE=default)"
	@echo "  make down          - Stop all services"
	@echo "  make logs          - View logs from all services"
	@echo "  make test          - Run test queries against the agent"
	@echo "  make clean         - Clean up Podman resources"
	@echo "  make pod-create    - Create a Podman pod (alternative to compose)"
	@echo "  make pod-start     - Start containers in Podman pod"
	@echo "  make pod-stop      - Stop Podman pod"
	@echo "  make pod-remove    - Remove Podman pod"
	@echo "  make sso-export    - Export AWS SSO credentials to .env (PROFILE=default)"
	@echo "  make sso-up        - Start with AWS SSO (mounts ~/.aws directory)"
	@echo "  make push-images   - Build and push images to ECR"
	@echo "  make deploy-k8s    - Deploy to Kubernetes"
	@echo "  make delete-k8s    - Delete Kubernetes resources"

build:
	$(PODMAN_COMPOSE) -f podman-compose.yml build

up:
	$(PODMAN_COMPOSE) -f podman-compose.yml up -d
	@echo "Services starting..."
	@echo "Agent Service: http://localhost:8000"
	@echo "Filesystem MCP: http://localhost:3001"
	@echo "Calculator MCP: http://localhost:3002"

down:
	$(PODMAN_COMPOSE) -f podman-compose.yml down

logs:
	$(PODMAN_COMPOSE) -f podman-compose.yml logs -f

test:
	@echo "Testing agent service health..."
	curl -s http://localhost:8000/health | jq .
	@echo "\nListing available tools..."
	curl -s http://localhost:8000/tools | jq .
	@echo "\nRunning test calculation..."
	curl -s -X POST http://localhost:8000/agent/run \
		-H "Content-Type: application/json" \
		-d '{"message": "What is 10 + 5?"}' | jq .

clean:
	$(PODMAN_COMPOSE) -f podman-compose.yml down -v
	podman system prune -f

# Alternative: Using Podman pods directly (without compose)
pod-create:
	@echo "Creating Podman pod..."
	podman pod create --name bedrock-agent-pod \
		-p 8000:8000 \
		-p 3001:3001 \
		-p 3002:3002

pod-start:
	@echo "Building images..."
	podman build -t agent-service:latest ./agent-service
	podman build -t mcp-filesystem:latest ./mcp-servers/filesystem
	podman build -t mcp-calculator:latest ./mcp-servers/calculator
	@echo "Starting containers in pod..."
	podman run -d --pod bedrock-agent-pod \
		--name mcp-filesystem-container \
		-v ./workspace:/workspace:Z \
		-e PORT=3001 \
		-e WORKSPACE_ROOT=/workspace \
		mcp-filesystem:latest
	podman run -d --pod bedrock-agent-pod \
		--name mcp-calculator-container \
		-e PORT=3002 \
		mcp-calculator:latest
	podman run -d --pod bedrock-agent-pod \
		--name agent-service-container \
		--env-file .env \
		-e MCP_FILESYSTEM_URL=http://localhost:3001 \
		-e MCP_CALCULATOR_URL=http://localhost:3002 \
		agent-service:latest
	@echo "Containers started in pod bedrock-agent-pod"

pod-stop:
	podman pod stop bedrock-agent-pod

pod-remove:
	podman pod rm -f bedrock-agent-pod

# AWS SSO support
sso-export:
	@echo "Exporting AWS SSO credentials for profile: $(PROFILE)"
	./scripts/sso-to-env.sh $(PROFILE)
	@echo ""
	@echo "Credentials exported. Now restart containers:"
	@echo "  make down && make up"

sso-up:
	@echo "Starting services with AWS SSO support..."
	@if [ ! -d "$$HOME/.aws" ]; then \
		echo "Error: ~/.aws directory not found"; \
		echo "Please configure AWS SSO first: aws configure sso"; \
		exit 1; \
	fi
	@echo "Using AWS_PROFILE=$(PROFILE)"
	AWS_PROFILE=$(PROFILE) $(PODMAN_COMPOSE) -f podman-compose-sso.yml up -d
	@echo "Services started with AWS SSO credentials from ~/.aws"
	@echo ""
	@echo "Make sure you're logged in: aws sso login --profile $(PROFILE)"

up-sso:
	@echo "════════════════════════════════════════════"
	@echo "Starting with AWS SSO (Profile: $(PROFILE))"
	@echo "════════════════════════════════════════════"
	@echo ""
	@echo "Step 1/3: Exporting SSO credentials..."
	@./scripts/sso-to-env.sh $(PROFILE) || (echo "Failed to export credentials. Make sure you're logged in: aws sso login --profile $(PROFILE)" && exit 1)
	@echo ""
	@echo "Step 2/3: Stopping existing containers..."
	@$(PODMAN_COMPOSE) -f podman-compose.yml down 2>/dev/null || true
	@echo ""
	@echo "Step 3/3: Starting services..."
	@$(PODMAN_COMPOSE) -f podman-compose.yml up -d
	@echo ""
	@echo "════════════════════════════════════════════"
	@echo "Services started successfully! 🎉"
	@echo "════════════════════════════════════════════"
	@echo ""
	@echo "Services running at:"
	@echo "  • Agent Service:    http://localhost:8000"
	@echo "  • Filesystem MCP:   http://localhost:3001"
	@echo "  • Calculator MCP:   http://localhost:3002"
	@echo ""
	@echo "Next steps:"
	@echo "  • Test: ./test-agent.sh"
	@echo "  • Logs: make logs"
	@echo "  • Stop: make down"
	@echo ""
	@echo "⚠ Note: SSO credentials are temporary and will expire."
	@echo "   Re-run 'make up-sso' when they do."

# ECR/EKS deployment targets (customize these with your values)
ECR_REGISTRY ?= YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
AWS_REGION ?= us-east-1

push-images:
	@echo "Logging into ECR..."
	aws ecr get-login-password --region $(AWS_REGION) | \
		podman login --username AWS --password-stdin $(ECR_REGISTRY)

	@echo "Building and pushing agent-service..."
	podman build -t $(ECR_REGISTRY)/agent-service:latest ./agent-service
	podman push $(ECR_REGISTRY)/agent-service:latest

	@echo "Building and pushing mcp-filesystem..."
	podman build -t $(ECR_REGISTRY)/mcp-filesystem:latest ./mcp-servers/filesystem
	podman push $(ECR_REGISTRY)/mcp-filesystem:latest

	@echo "Building and pushing mcp-calculator..."
	podman build -t $(ECR_REGISTRY)/mcp-calculator:latest ./mcp-servers/calculator
	podman push $(ECR_REGISTRY)/mcp-calculator:latest

	@echo "All images pushed successfully!"

deploy-k8s:
	@echo "Deploying to Kubernetes..."
	kubectl apply -k k8s/
	@echo "Waiting for deployments to be ready..."
	kubectl wait --for=condition=available --timeout=300s \
		deployment/agent-service \
		deployment/mcp-filesystem \
		deployment/mcp-calculator \
		-n bedrock-agent
	@echo "Deployment complete!"
	kubectl get all -n bedrock-agent

delete-k8s:
	@echo "Deleting Kubernetes resources..."
	kubectl delete -k k8s/
