#!/bin/bash

echo "☁️ Quick Cloud Setup Test"
echo "========================="

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_failure() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️ $1${NC}"
}

# Check Docker
if command -v docker &> /dev/null; then
    print_success "Docker is installed"
else
    print_failure "Docker not found"
    exit 1
fi

# Check Docker Compose V2
if docker compose version &> /dev/null; then
    print_success "Docker Compose is installed"
else
    print_failure "Docker Compose not found"
    exit 1
fi

# Check if Docker is running
if docker info &> /dev/null; then
    print_success "Docker is running"
else
    print_failure "Docker is not running"
    exit 1
fi

# Quick build test
print_info "Testing Docker build..."
if docker build -t mcp-weather-test . > /dev/null 2>&1; then
    print_success "Docker build works"
else
    print_failure "Docker build failed"
    exit 1
fi

# Start development environment
print_info "Starting development environment..."
docker compose up -d

# Wait for startup
print_info "Waiting for containers..."
sleep 20

# Test health endpoint
print_info "Testing health endpoint..."
if curl -f http://localhost:3000/health > /dev/null 2>&1; then
    print_success "Cloud server is running"
else
    print_failure "Cloud server failed to start"
    docker compose logs mcp-weather-server
    docker compose down
    exit 1
fi

# Test MCP endpoint
print_info "Testing MCP functionality..."
RESPONSE=$(curl -s -X POST http://localhost:3000/mcp \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
    -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}')

if echo "$RESPONSE" | grep -q "get_current_weather"; then
    print_success "MCP tools working"
else
    print_failure "MCP tools not working"
    echo "Response: $RESPONSE"
fi

# Cleanup
print_info "Cleaning up..."
docker compose down
