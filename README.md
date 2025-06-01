# MCP Weather Server

A Model Context Protocol (MCP) server that integrates with OpenWeatherMap API to provide weather data. This implementation supports both local (stdio) and cloud (SSE) deployment options.

## Features

- Current weather information
- 5-day weather forecast
- Support for multiple temperature units (metric, imperial, kelvin)
- Cloud deployment ready with SSE transport
- Authentication with Personal Access Tokens (PAT)
- Health check endpoints
- CORS support
- Proper error handling

## Prerequisites

- Node.js 18 or higher
- OpenWeatherMap API key
- npm or yarn package manager

## Installation

1. Clone the repository:
```bash
git clone https://github.com/alexpigul/TestMCP.git
cd TestMCP
```

2. Install dependencies:
```bash
npm install
```

3. Create a `.env` file with your OpenWeatherMap API key:
```bash
OPENWEATHER_API_KEY=your_api_key_here
DEPLOYMENT_MODE=stdio  # or 'cloud' for SSE deployment
```

## Usage

### Local Development (stdio)

```bash
npm run dev
```

### Cloud Deployment

```bash
export DEPLOYMENT_MODE=cloud
npm run start:cloud
```

## API Endpoints (Cloud Mode)

- `/health` - Health check endpoint
- `/sse` - Server-Sent Events endpoint
- `/mcp` - Direct MCP communication endpoint

## Authentication

The server supports Personal Access Token (PAT) authentication in cloud mode:

```bash
# Using Bearer token (recommended)
curl -H "Authorization: Bearer mcp_dev_your_token" https://your-domain.com/sse

# Using x-api-key header (legacy)
curl -H "x-api-key: your_token" https://your-domain.com/sse
```

## Available Tools

1. `get_current_weather`
   - Gets current weather for a location
   - Parameters: location (required), units (optional)

2. `get_weather_forecast`
   - Gets 5-day weather forecast
   - Parameters: location (required), units (optional)

## License

MIT

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change. 