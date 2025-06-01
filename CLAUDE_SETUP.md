# Claude Desktop Setup Guide 🖥️

Complete guide to integrate the MCP Weather Server with Claude Desktop application.

## Prerequisites ✅

- ✅ Node.js 18+ installed
- ✅ Claude Desktop app installed
- ✅ OpenWeatherMap API key (yours: `6bb0e605343c674f8a58d1b5032e5cf5`)
- ✅ MCP Weather Server built and ready

## Step 1: Locate Claude Desktop Configuration

### Find your configuration file location:

| Operating System | Configuration Path |
|-----------------|-------------------|
| **macOS** | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| **Windows** | `%APPDATA%/Claude/claude_desktop_config.json` |
| **Linux** | `~/.config/claude/claude_desktop_config.json` |

### Your specific path (macOS):
```
/Users/mac/Library/Application Support/Claude/claude_desktop_config.json
```

## Step 2: Configure MCP Weather Server

### Option A: Use Existing Configuration (Recommended)
Your configuration is already set up at the correct location! Verify it contains:

```json
{
  "mcpServers": {
    "weather": {
      "command": "node",
      "args": ["/Users/mac/Source/TestMcp/dist/index.js"],
      "env": {
        "OPENWEATHER_API_KEY": "6bb0e605343c674f8a58d1b5032e5cf5",
        "DEPLOYMENT_MODE": "stdio"
      }
    }
  }
}
```

### Option B: Manual Configuration
If you need to create or modify the configuration:

1. **Create/Edit the configuration file:**
   ```bash
   mkdir -p "$HOME/Library/Application Support/Claude"
   nano "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
   ```

2. **Add the weather server configuration:**
   ```json
   {
     "mcpServers": {
       "weather": {
         "command": "node",
         "args": ["/Users/mac/Source/TestMcp/dist/index.js"],
         "env": {
           "OPENWEATHER_API_KEY": "6bb0e605343c674f8a58d1b5032e5cf5",
           "DEPLOYMENT_MODE": "stdio"
         }
       }
     }
   }
   ```

### Option C: Multiple Server Configuration
If you already have other MCP servers, add the weather server to your existing configuration:

```json
{
  "mcpServers": {
    "existing-server": {
      "command": "node",
      "args": ["/path/to/existing/server.js"]
    },
    "weather": {
      "command": "node",
      "args": ["/Users/mac/Source/TestMcp/dist/index.js"],
      "env": {
        "OPENWEATHER_API_KEY": "6bb0e605343c674f8a58d1b5032e5cf5",
        "DEPLOYMENT_MODE": "stdio"
      }
    }
  }
}
```

## Step 3: Restart Claude Desktop

### Complete restart process:
1. **Quit Claude Desktop completely**
   - macOS: `Cmd + Q` or Claude → Quit Claude
   - Windows: File → Exit
   - Linux: File → Quit

2. **Wait 5 seconds** for complete shutdown

3. **Restart Claude Desktop** from Applications/Start Menu

4. **Wait for startup** (may take 10-15 seconds for MCP servers to initialize)

## Step 4: Verify MCP Server Connection

### Check Claude Desktop logs (if needed):
1. **Open Developer Tools** in Claude Desktop:
   - macOS: `Cmd + Option + I`
   - Windows: `Ctrl + Shift + I`
   - Linux: `Ctrl + Shift + I`

2. **Look for MCP connection messages** in the Console tab:
   ```
   [MCP] Connected to weather server
   [MCP] Available tools: get_current_weather, get_weather_forecast
   ```

## Test Cases 🧪

### Test Case 1: Basic Weather Query

**Input:**
```
What's the weather in London?
```

**Expected Behavior:**
- Claude should use the `get_current_weather` tool
- Should return current weather information for London
- Response should include temperature, conditions, humidity, wind speed

**Expected Response Format:**
```
🌤️ Current Weather for London

🌡️ Temperature: 15°C (feels like 13°C)
📝 Conditions: light rain
💧 Humidity: 78%
💨 Wind Speed: 3.2 m/s
```

### Test Case 2: Weather with Specific Units

**Input:**
```
What's the temperature in New York in Fahrenheit?
```

**Expected Behavior:**
- Claude should use `get_current_weather` with `units: "imperial"`
- Temperature should be displayed in Fahrenheit
- Wind speed should be in mph

**Expected Response Format:**
```
🌤️ Current Weather for New York

🌡️ Temperature: 68°F (feels like 65°F)
📝 Conditions: clear sky
💧 Humidity: 45%
💨 Wind Speed: 5.2 mph
```

### Test Case 3: Weather Forecast

**Input:**
```
Get me the 5-day forecast for Tokyo
```

**Expected Behavior:**
- Claude should use the `get_weather_forecast` tool
- Should return forecast for multiple days
- Each day should include min/max temperatures

**Expected Response Format:**
```
🌤️ 5-Day Weather Forecast for Tokyo

📅 Mon Dec 04 2023
🌡️ 8°C - 15°C
📝 scattered clouds
💧 Humidity: 65%

📅 Tue Dec 05 2023
🌡️ 10°C - 17°C
📝 clear sky
💧 Humidity: 58%
...
```

### Test Case 4: Invalid Location

**Input:**
```
What's the weather in Nonexistentcity?
```

**Expected Behavior:**
- Should handle error gracefully
- Should display helpful error message

**Expected Response:**
```
Error: Location "Nonexistentcity" not found
```

### Test Case 5: Multiple Weather Queries

**Input:**
```
Compare the weather in London, Paris, and Tokyo
```

**Expected Behavior:**
- Claude should make multiple tool calls
- Should present weather data for all three cities
- Should format comparison clearly

## Verification Steps ✅

### 1. Configuration Verification
```bash
# Check configuration file exists and is valid
cat "$HOME/Library/Application Support/Claude/claude_desktop_config.json" | jq .
```

### 2. Server Binary Verification
```bash
# Verify the server binary exists and is executable
ls -la /Users/mac/Source/TestMcp/dist/index.js
```

### 3. API Key Verification
```bash
# Test API key directly (wait for activation if needed)
curl "https://api.openweathermap.org/data/2.5/weather?q=London&appid=6bb0e605343c674f8a58d1b5032e5cf5&units=metric"
```

### 4. Manual Server Test
```bash
# Test server manually before Claude integration
cd /Users/mac/Source/TestMcp
export OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | npm start
```

## Troubleshooting 🔧

### Issue 1: Claude Desktop doesn't recognize the weather server

**Symptoms:**
- No weather-related tool responses
- MCP connection errors in console

**Solutions:**
1. **Check file paths** - Ensure absolute path is correct:
   ```bash
   ls -la /Users/mac/Source/TestMcp/dist/index.js
   ```

2. **Verify Node.js path** - Ensure Claude can find node:
   ```bash
   which node
   # Update config with full path if needed: "/usr/local/bin/node"
   ```

3. **Check permissions:**
   ```bash
   chmod +x /Users/mac/Source/TestMcp/dist/index.js
   ```

### Issue 2: API Key Errors

**Symptoms:**
- "Weather API error: 401 Unauthorized"
- "Invalid API key" messages

**Solutions:**
1. **Wait for activation** - New API keys take 10-15 minutes
2. **Verify key** - Check OpenWeatherMap dashboard
3. **Test key manually:**
   ```bash
   curl "https://api.openweathermap.org/data/2.5/weather?q=London&appid=6bb0e605343c674f8a58d1b5032e5cf5"
   ```

### Issue 3: Server startup failures

**Symptoms:**
- MCP connection failed messages
- Server doesn't respond

**Solutions:**
1. **Check dependencies:**
   ```bash
   cd /Users/mac/Source/TestMcp
   npm install
   npm run build
   ```

2. **Test manually:**
   ```bash
   export OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
   node dist/index.js
   ```

3. **Check logs** - Look for error messages in terminal

### Issue 4: Configuration file issues

**Symptoms:**
- Claude Desktop won't start
- JSON parsing errors

**Solutions:**
1. **Validate JSON:**
   ```bash
   cat "$HOME/Library/Application Support/Claude/claude_desktop_config.json" | jq .
   ```

2. **Backup and recreate:**
   ```bash
   cp "$HOME/Library/Application Support/Claude/claude_desktop_config.json" backup.json
   # Recreate configuration
   ```

### Issue 5: Tools not appearing

**Symptoms:**
- Claude responds normally but doesn't use weather tools
- No tool calling behavior

**Solutions:**
1. **Verify tool registration:**
   ```bash
   echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start
   ```

2. **Restart Claude Desktop** completely

3. **Check for multiple MCP servers** - Ensure no conflicts

## Advanced Configuration 🚀

### Development vs Production Setup

**Development Configuration:**
```json
{
  "mcpServers": {
    "weather-dev": {
      "command": "node",
      "args": ["/Users/mac/Source/TestMcp/dist/index.js"],
      "env": {
        "OPENWEATHER_API_KEY": "6bb0e605343c674f8a58d1b5032e5cf5",
        "DEPLOYMENT_MODE": "stdio",
        "NODE_ENV": "development"
      }
    }
  }
}
```

**Production Configuration (Cloud):**
```json
{
  "mcpServers": {
    "weather-prod": {
      "type": "sse",
      "url": "https://your-weather-server.com/sse",
      "headers": {
        "Authorization": "Bearer mcp_prod_9f42b95e9aa5d3ce8f7ebe5ca27538b6"
      }
    }
  }
}
```

### Multiple Environment Setup

```json
{
  "mcpServers": {
    "weather-local": {
      "command": "node",
      "args": ["/Users/mac/Source/TestMcp/dist/index.js"],
      "env": {
        "OPENWEATHER_API_KEY": "6bb0e605343c674f8a58d1b5032e5cf5",
        "DEPLOYMENT_MODE": "stdio"
      }
    },
    "weather-cloud": {
      "type": "sse",
      "url": "http://localhost:3000/sse",
      "headers": {
        "Authorization": "Bearer mcp_dev_2a55e153d51b306bf650300f8c21f1cb"
      }
    }
  }
}
```

## Performance Tips 💡

1. **Use local (stdio) mode** for best performance with Claude Desktop
2. **Keep API key secure** - never commit to version control
3. **Monitor API usage** - Free tier has 1000 calls/day limit
4. **Restart Claude Desktop** after any configuration changes
5. **Use specific locations** - "London, UK" is better than just "London"

## Next Steps 🎯

After successful setup:

1. **Test all weather queries** from the test cases above
2. **Try different locations and units** to verify functionality
3. **Explore forecast capabilities** with 5-day weather predictions
4. **Consider cloud deployment** for shared team access
5. **Add more weather features** or integrate additional APIs

---

**Your setup is ready!** 🎉 Just restart Claude Desktop and start asking about the weather! 