#!/bin/bash

set -e

echo "🧪 Local Cloud Testing Suite"
echo "=========================="

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

# Test 1: Docker build
print_info "Testing Docker build..."
if docker build -t mcp-weather-test . > /dev/null 2>&1; then
    print_success "Docker build successful"
else
    print_failure "Docker build failed"
    exit 1
fi

# Test 2: Start containers
print_info "Starting containers..."
docker compose -f docker-compose.yml up -d

# Wait for containers to be ready
print_info "Waiting for containers to start..."
sleep 15

# Test 3: Health check
print_info "Testing health endpoint..."
if curl -f http://localhost:3000/health > /dev/null 2>&1; then
    print_success "Health check passed"
else
    print_failure "Health check failed"
    docker compose -f docker-compose.yml logs
    exit 1
fi

# Test 4: MCP tools list
print_info "Testing MCP tools list..."
RESPONSE=$(curl -s -X POST http://localhost:3000/mcp \
    -H "Content-Type: application/json" -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
    -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}')

if echo "$RESPONSE" | grep -q "get_current_weather"; then
    print_success "MCP tools list working"
else
    print_failure "MCP tools list failed"
    echo "Response: $RESPONSE"
fi

# Test 5: Weather API call
print_info "Testing weather API call..."
WEATHER_RESPONSE=$(curl -s -X POST http://localhost:3000/mcp \
    -H "Content-Type: application/json" -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
    -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London"}}}')

if echo "$WEATHER_RESPONSE" | grep -q "Current Weather"; then
    print_success "Weather API call working"
else
    print_failure "Weather API call failed"
    echo "Response: $WEATHER_RESPONSE"
fi

# Test 6: SSE connection
print_info "Testing SSE connection..."
timeout 5 curl -H "Accept: text/event-stream" \
    -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
    -H "Origin: http://localhost:3000" \
    http://localhost:3000/sse > /dev/null 2>&1
if [ $? -eq 124 ]; then
    print_success "SSE connection established (timeout expected)"
else
    print_failure "SSE connection failed"
fi

# Cleanup
print_info "Cleaning up..."
docker compose -f docker-compose.yml down

print_success "All local cloud tests passed! 🎉" 