# Podman Setup Guide

This guide covers installing and configuring Podman for use with the Bedrock Agent system.

## Why Podman?

Podman is a daemonless container engine that offers several advantages:

- **Rootless containers** - Enhanced security by running containers as non-root user
- **No daemon** - Unlike Docker, Podman doesn't require a background daemon
- **Compatible** - Uses OCI container format, works with existing Dockerfiles
- **Pod support** - Native Kubernetes pod support for local development
- **Drop-in replacement** - Can alias `podman` to `docker` for compatibility

## Installation

### Linux (Recommended)

#### Fedora / RHEL / CentOS
```bash
sudo dnf install -y podman podman-compose
```

#### Ubuntu / Debian
```bash
sudo apt-get update
sudo apt-get install -y podman podman-compose
```

#### Arch Linux
```bash
sudo pacman -S podman podman-compose
```

### macOS

Install Podman Desktop (includes Podman and podman-compose):

```bash
# Using Homebrew
brew install podman podman-compose

# Initialize and start Podman machine
podman machine init
podman machine start
```

Or download Podman Desktop from: https://podman-desktop.io/

### Windows

Download and install Podman Desktop from: https://podman-desktop.io/

Or using WSL2:
1. Install WSL2 with a Linux distribution
2. Follow Linux installation steps inside WSL2

## Verify Installation

```bash
# Check Podman version
podman --version

# Check podman-compose (if installed separately)
podman-compose --version

# Or check built-in compose support
podman compose version

# Run test container
podman run --rm hello-world
```

## Configuration for This Project

### 1. Enable Rootless Mode (Linux)

Podman runs rootless by default on most systems. Verify:

```bash
podman info | grep rootless
# Should show: rootless: true
```

If running as root, switch to rootless:

```bash
# Enable user namespaces
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# Logout and login again, then verify
podman unshare cat /proc/self/uid_map
```

### 2. SELinux Configuration (RHEL/Fedora/CentOS)

If using SELinux, volume mounts need the `:Z` or `:z` flag:

```bash
# Already configured in podman-compose.yml
# Format: /host/path:/container/path:Z
```

- `:Z` - Private unshared label (recommended for single container)
- `:z` - Shared label (for multiple containers)

### 3. Configure Resource Limits (macOS/Windows)

For Podman Machine, adjust CPU and memory:

```bash
# Stop the machine
podman machine stop

# Set resources (4 CPUs, 8GB RAM)
podman machine set --cpus 4 --memory 8192

# Start the machine
podman machine start
```

### 4. Network Configuration

Podman creates networks differently than Docker:

```bash
# List networks
podman network ls

# Inspect the bridge network
podman network inspect bridge

# If needed, create a new network
podman network create bedrock-network
```

## Working with Podman Compose

### Option 1: podman-compose (Python-based)

```bash
# Install if not already installed
pip install podman-compose

# Use like docker-compose
podman-compose -f podman-compose.yml up -d
podman-compose -f podman-compose.yml down
```

### Option 2: podman compose (Built-in)

Newer versions of Podman include built-in compose support:

```bash
# Use compose subcommand
podman compose -f podman-compose.yml up -d
podman compose -f podman-compose.yml down
```

### Option 3: Native Podman Pods

Podman has native pod support (similar to Kubernetes pods):

```bash
# Create a pod
make pod-create

# Start containers in the pod
make pod-start

# Check pod status
podman pod ps

# Stop the pod
make pod-stop

# Remove the pod
make pod-remove
```

## Common Podman Commands

```bash
# Container management
podman ps                    # List running containers
podman ps -a                 # List all containers
podman logs <container>      # View container logs
podman exec -it <container> /bin/bash  # Shell into container
podman stop <container>      # Stop a container
podman rm <container>        # Remove a container

# Pod management
podman pod ps                # List pods
podman pod inspect <pod>     # Inspect pod
podman pod logs <pod>        # View pod logs
podman pod stop <pod>        # Stop a pod
podman pod rm <pod>          # Remove a pod

# Image management
podman images                # List images
podman build -t name:tag .   # Build image
podman rmi <image>           # Remove image
podman pull <image>          # Pull image
podman push <image>          # Push image

# System management
podman system prune          # Clean up unused resources
podman system df             # Show disk usage
podman info                  # System information
```

## Troubleshooting

### Permission Denied Errors

```bash
# Check if running rootless
podman info | grep rootless

# Check subuid/subgid configuration
cat /etc/subuid
cat /etc/subgid

# Should see your username with ranges like:
# username:100000:65536
```

### Volume Mount Issues

```bash
# On SELinux systems, use :Z flag
podman run -v ./data:/data:Z image:tag

# Check SELinux status
getenforce

# Temporarily disable for testing (not recommended for production)
sudo setenforce 0
```

### Port Binding Issues (Rootless)

Ports below 1024 require root. Solutions:

```bash
# Option 1: Use ports >= 1024 (already configured)
# Our services use 8000, 3001, 3002 - all above 1024

# Option 2: Allow specific ports for rootless
echo "net.ipv4.ip_unprivileged_port_start=80" | \
  sudo tee /etc/sysctl.d/99-podman.conf
sudo sysctl --system
```

### Podman Machine Not Starting (macOS/Windows)

```bash
# Remove and recreate the machine
podman machine stop
podman machine rm
podman machine init --cpus 4 --memory 8192 --disk-size 50
podman machine start
```

### Network Connectivity Issues

```bash
# Reset networking
podman system reset --force

# Or recreate network
podman network rm agent-network
podman network create agent-network
```

### "No such image" When Using Compose

```bash
# Build images explicitly
podman-compose -f podman-compose.yml build

# Or use Makefile
make build
```

## Docker Compatibility

If you want to use Docker commands with Podman:

```bash
# Create an alias
alias docker=podman
alias docker-compose=podman-compose

# Add to ~/.bashrc or ~/.zshrc
echo "alias docker=podman" >> ~/.bashrc
echo "alias docker-compose=podman-compose" >> ~/.bashrc
```

## Performance Tuning

### Increase Resource Limits

```bash
# For rootless containers, increase limits
sudo vi /etc/security/limits.conf
# Add:
# username soft nofile 65536
# username hard nofile 65536
```

### Use Overlay Storage Driver

```bash
# Check current storage driver
podman info | grep graphDriverName

# Should show: overlay

# If not, configure in /etc/containers/storage.conf
```

### Enable Parallel Downloads

```bash
# Edit /etc/containers/registries.conf
# Add:
[engine]
max_parallel_downloads = 10
```

## Best Practices

1. **Always run rootless** unless you specifically need root privileges
2. **Use :Z flag** for volume mounts on SELinux systems
3. **Clean up regularly** with `podman system prune`
4. **Use pods** for multi-container applications instead of compose when possible
5. **Pin image versions** in production (avoid :latest tag)
6. **Enable image scanning** for security: `podman scan <image>`

## Migration from Docker

If you're migrating from Docker:

```bash
# Export Docker image
docker save image:tag -o image.tar

# Import to Podman
podman load -i image.tar

# Or use alias approach
alias docker=podman
# Now all docker commands use podman
```

## Additional Resources

- Official Documentation: https://docs.podman.io/
- Podman Desktop: https://podman-desktop.io/
- Tutorials: https://github.com/containers/podman/tree/main/docs/tutorials
- Rootless Guide: https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md

## Quick Reference Card

```bash
# Start services
make build && make up

# View logs
make logs

# Stop services
make down

# Clean everything
make clean

# Using pods directly
make pod-create && make pod-start
make pod-stop
make pod-remove

# Check status
podman ps           # containers
podman pod ps       # pods
podman images       # images
```

## Support

If you encounter issues:

1. Check Podman version: `podman --version` (4.0+ recommended)
2. Review logs: `journalctl --user -u podman`
3. Check system info: `podman info`
4. Verify configuration: `cat ~/.config/containers/containers.conf`
5. Consult troubleshooting section above

For project-specific issues, see [QUICKSTART.md](QUICKSTART.md) or [README.md](README.md).
