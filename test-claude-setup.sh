#!/bin/bash

set -e

echo "🧪 Claude Desktop MCP Weather Server Test Suite"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ PASS${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_failure() {
    echo -e "${RED}❌ FAIL${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠️ WARN${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ️ INFO${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}$1${NC}"
    echo "----------------------------------------"
}

increment_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Detect OS
OS=$(uname -s)
case $OS in
    Darwin)
        CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Claude"
        ;;
    Linux)
        CLAUDE_CONFIG_DIR="$HOME/.config/claude"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        CLAUDE_CONFIG_DIR="$APPDATA/Claude"
        ;;
    *)
        print_failure "Unknown OS: $OS"
        exit 1
        ;;
esac

CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"
PROJECT_DIR="/Users/mac/Source/TestMcp"
API_KEY="6bb0e605343c674f8a58d1b5032e5cf5"

# Test 1: Check Node.js installation
print_header "Test 1: Node.js Environment"
increment_test
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    NODE_MAJOR=$(echo $NODE_VERSION | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_MAJOR" -ge "18" ]; then
        print_success "Node.js $NODE_VERSION (required: 18+)"
    else
        print_failure "Node.js version too old: $NODE_VERSION (required: 18+)"
    fi
else
    print_failure "Node.js not found"
fi

# Test 2: Check project structure
print_header "Test 2: Project Structure"

increment_test
if [ -d "$PROJECT_DIR" ]; then
    print_success "Project directory exists: $PROJECT_DIR"
else
    print_failure "Project directory not found: $PROJECT_DIR"
fi

increment_test
if [ -f "$PROJECT_DIR/package.json" ]; then
    print_success "package.json exists"
else
    print_failure "package.json not found"
fi

increment_test
if [ -f "$PROJECT_DIR/dist/index.js" ]; then
    print_success "Compiled server exists: dist/index.js"
else
    print_failure "Compiled server not found. Run: npm run build"
fi

increment_test
if [ -d "$PROJECT_DIR/node_modules" ]; then
    print_success "Dependencies installed (node_modules exists)"
else
    print_failure "Dependencies not installed. Run: npm install"
fi

# Test 3: Check Claude Desktop configuration
print_header "Test 3: Claude Desktop Configuration"

increment_test
if [ -d "$CLAUDE_CONFIG_DIR" ]; then
    print_success "Claude config directory exists: $CLAUDE_CONFIG_DIR"
else
    print_failure "Claude config directory not found: $CLAUDE_CONFIG_DIR"
fi

increment_test
if [ -f "$CLAUDE_CONFIG_FILE" ]; then
    print_success "Claude configuration file exists"
    
    # Validate JSON structure
    if jq . "$CLAUDE_CONFIG_FILE" > /dev/null 2>&1; then
        print_success "Configuration file is valid JSON"
        
        # Check for MCP servers
        if jq -e '.mcpServers' "$CLAUDE_CONFIG_FILE" > /dev/null 2>&1; then
            print_success "mcpServers section found"
            
            # Check for weather server
            if jq -e '.mcpServers.weather' "$CLAUDE_CONFIG_FILE" > /dev/null 2>&1; then
                print_success "Weather server configuration found"
                
                # Check command and args
                COMMAND=$(jq -r '.mcpServers.weather.command' "$CLAUDE_CONFIG_FILE")
                ARGS=$(jq -r '.mcpServers.weather.args[0]' "$CLAUDE_CONFIG_FILE")
                API_KEY_CONFIG=$(jq -r '.mcpServers.weather.env.OPENWEATHER_API_KEY' "$CLAUDE_CONFIG_FILE")
                
                increment_test
                if [ "$COMMAND" = "node" ]; then
                    print_success "Correct command: $COMMAND"
                else
                    print_failure "Incorrect command: $COMMAND (expected: node)"
                fi
                
                increment_test
                if [ "$ARGS" = "$PROJECT_DIR/dist/index.js" ]; then
                    print_success "Correct server path: $ARGS"
                else
                    print_failure "Incorrect server path: $ARGS (expected: $PROJECT_DIR/dist/index.js)"
                fi
                
                increment_test
                if [ "$API_KEY_CONFIG" = "$API_KEY" ]; then
                    print_success "API key configured correctly"
                elif [ "$API_KEY_CONFIG" = "your_api_key_here" ]; then
                    print_failure "API key not updated (still placeholder)"
                else
                    print_warning "API key configured but different from expected"
                fi
            else
                increment_test
                print_failure "Weather server not found in configuration"
            fi
        else
            increment_test
            print_failure "mcpServers section not found"
        fi
    else
        increment_test
        print_failure "Configuration file is not valid JSON"
    fi
else
    increment_test
    print_failure "Claude configuration file not found: $CLAUDE_CONFIG_FILE"
fi

# Test 4: API Key validation
print_header "Test 4: OpenWeatherMap API Key"

increment_test
print_info "Testing API key: ${API_KEY:0:8}..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://api.openweathermap.org/data/2.5/weather?q=London&appid=$API_KEY&units=metric")

if [ "$HTTP_STATUS" = "200" ]; then
    print_success "API key is valid and active"
elif [ "$HTTP_STATUS" = "401" ]; then
    print_failure "API key is invalid or not activated yet (wait 10-15 minutes)"
elif [ "$HTTP_STATUS" = "000" ]; then
    print_warning "Network error - check internet connection"
else
    print_warning "Unexpected API response: HTTP $HTTP_STATUS"
fi

# Test 5: Manual server test
print_header "Test 5: MCP Server Functionality"

increment_test
print_info "Testing server startup and tool registration..."
cd "$PROJECT_DIR"

# Test tools list
TOOLS_OUTPUT=$(echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | OPENWEATHER_API_KEY="$API_KEY" timeout 10 npm start 2>/dev/null | tail -1)

if echo "$TOOLS_OUTPUT" | grep -q "get_current_weather"; then
    print_success "Server responds and registers weather tools"
else
    print_failure "Server doesn't respond or tools not registered"
fi

# Test weather tool (if API key works)
if [ "$HTTP_STATUS" = "200" ]; then
    increment_test
    print_info "Testing weather tool functionality..."
    WEATHER_OUTPUT=$(echo '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London", "units": "metric"}}}' | OPENWEATHER_API_KEY="$API_KEY" timeout 15 npm start 2>/dev/null | tail -1)
    
    if echo "$WEATHER_OUTPUT" | grep -q "Current Weather for"; then
        print_success "Weather tool returns valid data"
    elif echo "$WEATHER_OUTPUT" | grep -q "Weather API error"; then
        print_failure "Weather tool returns API error"
    else
        print_warning "Weather tool response unclear"
    fi
fi

# Test 6: File permissions
print_header "Test 6: File Permissions"

increment_test
if [ -r "$PROJECT_DIR/dist/index.js" ]; then
    print_success "Server file is readable"
else
    print_failure "Server file is not readable"
fi

increment_test
if [ -x "$(which node)" ]; then
    print_success "Node.js is executable"
else
    print_failure "Node.js is not executable"
fi

# Test 7: Claude Desktop process check
print_header "Test 7: Claude Desktop Status"

increment_test
if pgrep -f "Claude" > /dev/null; then
    print_success "Claude Desktop is running"
    print_warning "Restart Claude Desktop to load MCP configuration"
else
    print_info "Claude Desktop is not running"
fi

# Test Summary
print_header "Test Summary"
echo "Total tests: $TOTAL_TESTS"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "ALL TESTS PASSED! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Restart Claude Desktop completely"
    echo "2. Test with: 'What's the weather in London?'"
    echo "3. Try: 'Get me the forecast for Tokyo'"
    exit 0
else
    print_failure "Some tests failed. Check the issues above."
    echo ""
    echo "Common fixes:"
    echo "1. Run: cd $PROJECT_DIR && npm install && npm run build"
    echo "2. Wait for API key activation (10-15 minutes)"
    echo "3. Restart Claude Desktop after fixing issues"
    exit 1
fi 