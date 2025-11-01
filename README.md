# AWS Bedrock Agent with MCP Servers

A containerized agent system that uses AWS Bedrock for LLM inference with custom MCP (Model Context Protocol) servers, deployable on EKS or locally via Podman.

## Architecture

```
┌─────────────────┐
│   User/Client   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Agent Service  │  ← Orchestrates agent loop, calls Bedrock API
└────────┬────────┘
         │
         ├─────────────┬──────────────┐
         ▼             ▼              ▼
┌─────────────┐  ┌──────────┐  ┌──────────┐
│ AWS Bedrock │  │   MCP    │  │   MCP    │
│   (Claude)  │  │FileSystem│  │Calculator│
└─────────────┘  └──────────┘  └──────────┘
```

## Components

### Agent Service (Python + FastAPI)
- Orchestrates the agent loop
- Calls AWS Bedrock Converse API
- Manages tool execution via MCP servers
- Exposes REST API for agent interactions

### MCP Servers (Node.js + Express)

#### Filesystem Server
Tools for file operations:
- `read_file` - Read file contents
- `write_file` - Write to files
- `list_directory` - List directory contents
- `create_directory` - Create directories

#### Calculator Server
Tools for math operations:
- `add`, `subtract`, `multiply`, `divide`
- `power` - Exponentiation
- `sqrt` - Square root

## Prerequisites

### For Local Development (Podman)
- Podman & podman-compose (or use `podman compose`) - See [PODMAN_SETUP.md](PODMAN_SETUP.md)
- AWS credentials with Bedrock access
- AWS CLI configured

**Note:**
- Migrating from Docker? See [MIGRATION_FROM_DOCKER.md](MIGRATION_FROM_DOCKER.md)
- Using AWS SSO? See [AWS_SSO_SETUP.md](AWS_SSO_SETUP.md) or [SSO_QUICK_REFERENCE.md](SSO_QUICK_REFERENCE.md)
- Getting model invocation errors? See [BEDROCK_MODEL_UPDATE.md](BEDROCK_MODEL_UPDATE.md)

### For EKS Deployment
- AWS Account with EKS cluster
- kubectl configured
- IAM role for service accounts (IRSA) set up
- ECR repositories for container images
- Podman for building and pushing images
- (Optional) EFS CSI driver for shared storage

## Local Setup with Podman

### 1. Configure AWS Credentials

Create a `.env` file:

```bash
cat > .env <<EOF
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
# AWS_SESSION_TOKEN=your_session_token  # If using temporary credentials
EOF
```

### 2. Build and Run

```bash
# Using Makefile (recommended)
make build
make up

# Or using podman-compose directly
podman-compose -f podman-compose.yml build
podman-compose -f podman-compose.yml up -d

# Or using podman compose (newer syntax)
podman compose -f podman-compose.yml up -d

# Alternative: Use native Podman pods
make pod-create
make pod-start
```

Services will be available at:
- Agent Service: http://localhost:8000
- Filesystem MCP: http://localhost:3001
- Calculator MCP: http://localhost:3002

### 3. Test the Agent

```bash
# List available tools
curl http://localhost:8000/tools

# Run an agent query
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Calculate 25 * 4 and then add 10 to the result",
    "max_turns": 10
  }'
```

### 4. Example Requests

#### Math calculation:
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is the square root of 144?"
  }'
```

#### File operations:
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Create a file called test.txt with the content Hello World"
  }'
```

#### Combined operations:
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Calculate 10 + 5, then write the result to a file called result.txt"
  }'
```

### 5. View Logs

```bash
# All services
make logs

# Or with podman-compose
podman-compose -f podman-compose.yml logs -f

# Specific service
podman-compose -f podman-compose.yml logs -f agent-service

# With podman pod
podman logs agent-service
podman pod logs bedrock-agent-pod
```

### 6. Stop Services

```bash
# Using compose
make down

# Or with podman-compose
podman-compose -f podman-compose.yml down

# With podman pod
make pod-stop
make pod-remove
```

## EKS Deployment

### 1. Set Up IAM Role for Service Accounts (IRSA)

Create an IAM policy for Bedrock access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/anthropic.claude-*"
    }
  ]
}
```

Create IAM role with trust policy for your EKS cluster:

```bash
# Create the role (replace with your account ID and cluster details)
eksctl create iamserviceaccount \
  --name bedrock-agent-sa \
  --namespace bedrock-agent \
  --cluster your-cluster-name \
  --attach-policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/BedrockInvokePolicy \
  --approve
```

### 2. Build and Push Container Images

```bash
# Configure ECR login with Podman
aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repositories
aws ecr create-repository --repository-name agent-service
aws ecr create-repository --repository-name mcp-filesystem
aws ecr create-repository --repository-name mcp-calculator

# Build and push agent service
cd agent-service
podman build -t YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/agent-service:latest .
podman push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/agent-service:latest

# Build and push filesystem server
cd ../mcp-servers/filesystem
podman build -t YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/mcp-filesystem:latest .
podman push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/mcp-filesystem:latest

# Build and push calculator server
cd ../calculator
podman build -t YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/mcp-calculator:latest .
podman push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/mcp-calculator:latest

# Or use the Makefile
make push-images ECR_REGISTRY=YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

### 3. Update Kubernetes Manifests

Edit `k8s/serviceaccount.yaml`:
```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-agent-role
```

Edit deployment files to use your ECR images:
```yaml
image: YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/agent-service:latest
```

### 4. Set Up EFS for Shared Storage (Optional)

If you need shared filesystem access:

```bash
# Install EFS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.7"

# Create EFS filesystem and storage class
# See: https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
```

### 5. Deploy to EKS

```bash
# Apply all manifests
kubectl apply -k k8s/

# Or apply individually
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/mcp-filesystem-deployment.yaml
kubectl apply -f k8s/mcp-calculator-deployment.yaml
kubectl apply -f k8s/agent-deployment.yaml
kubectl apply -f k8s/hpa.yaml
```

### 6. Verify Deployment

```bash
# Check all resources
kubectl get all -n bedrock-agent

# Check pod logs
kubectl logs -n bedrock-agent -l app=agent-service

# Get service endpoint
kubectl get svc -n bedrock-agent agent-service
```

### 7. Access the Agent Service

```bash
# Get the LoadBalancer URL
AGENT_URL=$(kubectl get svc -n bedrock-agent agent-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test the agent
curl -X POST http://$AGENT_URL/agent/run \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is 100 divided by 4?"
  }'
```

## Project Structure

```
.
├── agent-service/              # Python agent service
│   ├── app.py                 # Main FastAPI application
│   ├── requirements.txt       # Python dependencies
│   └── Dockerfile
├── mcp-servers/
│   ├── filesystem/            # Filesystem MCP server
│   │   ├── src/
│   │   │   └── index.ts
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── Dockerfile
│   └── calculator/            # Calculator MCP server
│       ├── src/
│       │   └── index.ts
│       ├── package.json
│       ├── tsconfig.json
│       └── Dockerfile
├── k8s/                       # Kubernetes manifests
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── configmap.yaml
│   ├── agent-deployment.yaml
│   ├── mcp-filesystem-deployment.yaml
│   ├── mcp-calculator-deployment.yaml
│   ├── hpa.yaml
│   └── kustomization.yaml
├── podman-compose.yml         # Podman Compose configuration
├── README.md                  # Full documentation
└── PODMAN_SETUP.md           # Podman installation and setup guide
```

## API Endpoints

### Agent Service

- `GET /` - Service info
- `GET /health` - Health check
- `GET /tools` - List all available tools
- `POST /agent/run` - Run agent with a message
  ```json
  {
    "message": "Your query here",
    "max_turns": 10
  }
  ```

### MCP Servers

- `GET /` - Server info
- `GET /tools` - List available tools
- `POST /execute` - Execute a tool
  ```json
  {
    "tool": "tool_name",
    "arguments": { "arg1": "value1" }
  }
  ```

## Adding New MCP Servers

To add a new MCP server:

1. Create a new directory under `mcp-servers/`
2. Implement the server with:
   - `GET /tools` endpoint returning tool definitions
   - `POST /execute` endpoint for tool execution
3. Add Dockerfile
4. Update `docker-compose.yml` to include the new service
5. Add Kubernetes deployment manifest
6. Update agent service environment to include the new server URL

## Monitoring and Debugging

### Local (Podman)

```bash
# View real-time logs
make logs
# Or
podman-compose -f podman-compose.yml logs -f

# Check container status
podman ps
# Or with compose
podman-compose -f podman-compose.yml ps

# Check pod status (if using pods)
podman pod ps
podman pod inspect bedrock-agent-pod

# Restart a service
podman restart agent-service
# Or with compose
podman-compose -f podman-compose.yml restart agent-service
```

### EKS

```bash
# View logs
kubectl logs -n bedrock-agent -l app=agent-service -f

# Check pod status
kubectl get pods -n bedrock-agent

# Describe pod for troubleshooting
kubectl describe pod -n bedrock-agent <pod-name>

# Check HPA status
kubectl get hpa -n bedrock-agent

# Port forward for local testing
kubectl port-forward -n bedrock-agent svc/agent-service 8000:80
```

## Cost Optimization

- Use Bedrock's on-demand pricing (no upfront commitments)
- Scale MCP servers based on load using HPA
- Use spot instances for non-production EKS node groups
- Monitor Bedrock API usage via CloudWatch

## Security Best Practices

1. **Never commit AWS credentials** - Use IRSA for EKS or environment variables locally
2. **Restrict Bedrock IAM permissions** - Only allow specific model invocations
3. **Use private subnets** - Deploy MCP servers in private subnets
4. **Enable pod security standards** - Use Kubernetes security contexts
5. **Scan container images** - Use ECR image scanning
6. **Limit filesystem access** - Mount only necessary directories

## Troubleshooting

### Agent can't connect to Bedrock
- Check AWS credentials are configured
- Verify IAM permissions include `bedrock:InvokeModel`
- Ensure the model ID is correct and available in your region

### MCP servers not responding
- Check MCP server logs for errors
- Verify network connectivity between services
- Ensure environment variables are set correctly

### Tools not appearing
- Check MCP server `/tools` endpoint returns valid schemas
- Verify agent service can reach MCP server URLs
- Review agent service logs for tool fetching errors

## License

MIT

## Contributing

Contributions welcome! Please open an issue or submit a pull request.
