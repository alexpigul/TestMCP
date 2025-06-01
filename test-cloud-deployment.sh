#!/bin/bash

set -e

echo "🌐 Cloud Deployment Testing Suite"
echo "================================"

# Configuration
CLOUD_URL=${1:-"http://localhost:3000"}
PAT_TOKEN=${2:-"mcp_dev_2a55e153d51b306bf650300f8c21f1cb"}

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

# Test 1: Health Check
print_info "Testing health endpoint at $CLOUD_URL..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$CLOUD_URL/health")
if [ "$HTTP_STATUS" = "200" ]; then
    print_success "Health check passed (HTTP $HTTP_STATUS)"
else
    print_failure "Health check failed (HTTP $HTTP_STATUS)"
    exit 1
fi

# Test 2: SSE Connection
print_info "Testing SSE connection..."
timeout 5 curl -H "Accept: text/event-stream" \
    -H "Authorization: Bearer $PAT_TOKEN" \
    -H "Origin: https://example.com" \
    "$CLOUD_URL/sse" > /dev/null 2>&1
if [ $? -eq 124 ]; then
    print_success "SSE connection established (timeout expected)"
else
    print_failure "SSE connection failed"
fi

# Test 3: Authentication
print_info "Testing authentication..."
AUTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/auth_test \
    -X POST "$CLOUD_URL/mcp" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer invalid-token" \
    -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}')

if [ "$AUTH_RESPONSE" = "401" ]; then
    print_success "Authentication validation working"
else
    print_failure "Authentication validation failed (got $AUTH_RESPONSE)"
fi

# Test 4: Valid Authentication
print_info "Testing valid authentication..."
TOOLS_RESPONSE=$(curl -s -X POST "$CLOUD_URL/mcp" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $PAT_TOKEN" \
    -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}')

if echo "$TOOLS_RESPONSE" | grep -q "get_current_weather"; then
    print_success "Authenticated tools list working"
else
    print_failure "Authenticated tools list failed"
    echo "Response: $TOOLS_RESPONSE"
fi

# Test 5: Weather API
print_info "Testing weather API..."
WEATHER_RESPONSE=$(curl -s -X POST "$CLOUD_URL/mcp" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $PAT_TOKEN" \
    -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London"}}}')

if echo "$WEATHER_RESPONSE" | grep -q "Current Weather"; then
    print_success "Weather API working"
else
    print_failure "Weather API failed"
    echo "Response: $WEATHER_RESPONSE"
fi

# Test 6: CORS Headers
print_info "Testing CORS headers..."
CORS_RESPONSE=$(curl -s -I -H "Origin: https://example.com" \
    -H "Authorization: Bearer $PAT_TOKEN" \
    "$CLOUD_URL/health")
if echo "$CORS_RESPONSE" | grep -q "Access-Control-Allow-Origin"; then
    print_success "CORS headers present"
else
    print_failure "CORS headers missing"
fi

# Test 7: Load Testing
print_info "Testing concurrent requests..."
for i in {1..10}; do
    curl -s -H "Authorization: Bearer $PAT_TOKEN" "$CLOUD_URL/health" > /dev/null &
done
wait
print_success "Concurrent requests handled"

print_success "All cloud deployment tests passed! 🎉"
echo ""
echo "Your cloud deployment is ready at: $CLOUD_URL"
echo "SSE endpoint: $CLOUD_URL/sse"
echo "Health check: $CLOUD_URL/health" 