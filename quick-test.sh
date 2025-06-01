#!/bin/bash

echo "🌤️ Quick Claude Desktop Integration Test"
echo "========================================"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test configuration exists
CONFIG_FILE="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}✅ Claude Desktop configuration exists${NC}"
else
    echo -e "${RED}❌ Configuration missing${NC}"
    exit 1
fi

# Test server responds
echo "Testing MCP server..."
RESPONSE=$(echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start 2>/dev/null | tail -1)

if echo "$RESPONSE" | grep -q "get_current_weather"; then
    echo -e "${GREEN}✅ MCP server working${NC}"
else
    echo -e "${RED}❌ MCP server not responding${NC}"
    exit 1
fi

# Test weather API
echo "Testing weather API..."
WEATHER=$(echo '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London"}}}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start 2>/dev/null | tail -1)

if echo "$WEATHER" | grep -q "Current Weather for London"; then
    echo -e "${GREEN}✅ Weather API working${NC}"
else
    echo -e "${RED}❌ Weather API not working${NC}"
    exit 1
fi