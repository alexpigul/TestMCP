# MCP Weather Server Testing Reference 🧪

## Quick Status Check ✅

Run this to verify everything is ready:
```bash
./quick-test.sh
```

## Claude Desktop Test Cases 🖥️

### Basic Functionality Tests

#### Test 1: Simple Weather Query
**Input to Claude:**
```
What's the weather in London?
```

**Expected Response:**
```
🌤️ Current Weather for London

🌡️ Temperature: 20°C (feels like 20°C)
📝 Conditions: overcast clouds
💧 Humidity: 68%
💨 Wind Speed: 4.63 m/s
```

**Verification:**
- Claude should automatically use the `get_current_weather` tool
- Response should include temperature, conditions, humidity, and wind speed
- Should use metric units by default

#### Test 2: Weather with Specific Units
**Input to Claude:**
```
What's the temperature in New York in Fahrenheit?
```

**Expected Response:**
```
🌤️ Current Weather for New York

🌡️ Temperature: 68°F (feels like 65°F)
📝 Conditions: clear sky
💧 Humidity: 45%
💨 Wind Speed: 5.2 mph
```

**Verification:**
- Temperature should be in Fahrenheit (°F)
- Wind speed should be in mph
- Should automatically detect imperial units request

#### Test 3: Weather Forecast
**Input to Claude:**
```
Get me the 5-day forecast for Tokyo
```

**Expected Response:**
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

**Verification:**
- Should use the `get_weather_forecast` tool
- Should show multiple days (up to 5)
- Each day should include min/max temperatures

### Advanced Test Cases

#### Test 4: Multiple Locations
**Input to Claude:**
```
Compare the weather in London, Paris, and Tokyo
```

**Expected Behavior:**
- Claude should make 3 separate tool calls
- Should present data for all three cities
- Should format comparison clearly

#### Test 5: Specific Location Formats
**Input to Claude:**
```
What's the weather in:
- London, UK
- New York, NY, USA
- Sydney, Australia
```

**Expected Behavior:**
- Should handle various location formats
- Should disambiguate common city names
- Should return accurate location-specific data

#### Test 6: Error Handling
**Input to Claude:**
```
What's the weather in Nonexistentcity?
```

**Expected Response:**
```
I encountered an error when trying to get weather data: Location "Nonexistentcity" not found.
```

**Verification:**
- Should handle invalid locations gracefully
- Should provide helpful error messages
- Should not crash or hang

### Edge Cases

#### Test 7: Empty/Invalid Requests
**Input to Claude:**
```
Get weather for
```

**Expected Behavior:**
- Should prompt for a location
- Should not make API calls with empty parameters

#### Test 8: Rate Limiting
**Input to Claude:**
```
Get weather for London, Paris, Tokyo, New York, Sydney, Berlin, Rome, Madrid, Amsterdam, Vienna
```

**Expected Behavior:**
- Should handle multiple rapid requests
- Should respect API rate limits
- Should not fail due to too many requests

## Manual Testing Commands 🔧

### Test Server Startup
```bash
cd /Users/mac/Source/TestMcp
export OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
npm start
```

### Test Tools List
```bash
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start
```

### Test Current Weather
```bash
echo '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London", "units": "metric"}}}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start
```

### Test Weather Forecast
```bash
echo '{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "get_weather_forecast", "arguments": {"location": "Tokyo", "units": "metric"}}}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start
```

### Test Different Units
```bash
# Imperial (Fahrenheit, mph)
echo '{"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "New York", "units": "imperial"}}}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start

# Kelvin
echo '{"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London", "units": "kelvin"}}}' | OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start
```

## Configuration Verification 🔍

### Check Claude Desktop Config
```bash
cat "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
```

**Expected Output:**
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

### Validate JSON Structure
```bash
cat "$HOME/Library/Application Support/Claude/claude_desktop_config.json" | jq .
```

### Check API Key Status
```bash
curl "https://api.openweathermap.org/data/2.5/weather?q=London&appid=6bb0e605343c674f8a58d1b5032e5cf5&units=metric"
```

**Expected Response (if working):**
```json
{
  "weather": [{"main": "Clouds", "description": "overcast clouds"}],
  "main": {"temp": 20, "feels_like": 20, "humidity": 68},
  "wind": {"speed": 4.63},
  "name": "London"
}
```

## Troubleshooting Guide 🔧

### Issue: Claude Desktop doesn't use weather tools

**Symptoms:**
- Claude responds normally but doesn't call weather tools
- No weather data in responses

**Solution:**
1. Restart Claude Desktop completely (`Cmd+Q`, then reopen)
2. Check configuration file exists and is valid
3. Verify file paths are absolute and correct
4. Check Claude Desktop developer console for errors

### Issue: Weather tools fail with API errors

**Symptoms:**
- "Weather API error: 401 Unauthorized"
- "Invalid API key" messages

**Solution:**
1. Verify API key is correct: `6bb0e605343c674f8a58d1b5032e5cf5`
2. Test API key manually with curl command above
3. Wait if key was recently generated (10-15 minutes)
4. Check OpenWeatherMap dashboard for key status

### Issue: Server startup failures

**Symptoms:**
- MCP connection failed in Claude Desktop
- Server doesn't respond to manual tests

**Solution:**
1. Rebuild project: `npm run build`
2. Reinstall dependencies: `npm install`
3. Check Node.js version: `node --version` (need 18+)
4. Test manually with commands above

### Issue: Permissions errors

**Symptoms:**
- "Permission denied" errors
- "Command not found" errors

**Solution:**
1. Make server executable: `chmod +x dist/index.js`
2. Check Node.js path: `which node`
3. Use full Node.js path in config if needed

## Performance Expectations 📊

### Response Times
- Tool list: < 100ms
- Current weather: < 2 seconds
- Weather forecast: < 3 seconds

### API Limits
- Free tier: 1,000 calls/day, 60 calls/minute
- Monitor usage at OpenWeatherMap dashboard

### Resource Usage
- Memory: ~50MB per server instance
- CPU: Minimal (event-driven)
- Network: ~1-5KB per weather request

## Success Criteria ✅

Your MCP Weather Server is working correctly if:

1. ✅ `./quick-test.sh` shows all green checkmarks
2. ✅ Claude Desktop shows weather tools in developer console
3. ✅ Weather queries return properly formatted responses
4. ✅ Multiple unit types work (metric, imperial, kelvin)
5. ✅ Error handling works for invalid locations
6. ✅ Forecast tool returns multi-day data

## Development Testing 🛠️

### Test New Features
```bash
# Test in development mode
npm run dev

# Test with different environments
DEPLOYMENT_MODE=cloud npm start
```

### Cloud Testing
```bash
# Start cloud server
DEPLOYMENT_MODE=cloud OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5 npm start

# Test health endpoint
curl http://localhost:3000/health

# Test with authentication
curl -X POST http://localhost:3000/mcp \
  -H "Authorization: Bearer mcp_dev_2a55e153d51b306bf650300f8c21f1cb" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

---

**Ready to test!** 🚀 Start with `./quick-test.sh` then restart Claude Desktop and try the test cases above. 