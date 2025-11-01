#!/bin/bash

# Docker to Podman Alias Script
# Source this file to use docker/docker-compose commands with Podman
# Usage: source scripts/docker-alias.sh

# Check if Podman is installed
if ! command -v podman &> /dev/null; then
    echo "Error: Podman is not installed. Please install Podman first."
    echo "See PODMAN_SETUP.md for installation instructions."
    return 1 2>/dev/null || exit 1
fi

# Create aliases
alias docker='podman'
alias docker-compose='podman-compose'

echo "Docker compatibility aliases activated!"
echo "  docker -> podman"
echo "  docker-compose -> podman-compose"
echo ""
echo "You can now use 'docker' and 'docker-compose' commands."
echo "These will be translated to their Podman equivalents."
echo ""
echo "To make this permanent, add the following to your ~/.bashrc or ~/.zshrc:"
echo "  alias docker=podman"
echo "  alias docker-compose=podman-compose"
