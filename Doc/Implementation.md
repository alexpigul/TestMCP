# MCP Server Implementation Guide - External API Integration

## Overview

This guide demonstrates how to create a Model Context Protocol (MCP) server that integrates with external APIs. We'll build a weather server that calls the OpenWeatherMap API to provide current weather and forecast data. The implementation supports both local (stdio) and cloud (SSE) deployment options.

## Project Structure

```
mcp-weather-server/
├── src/
│   └── index.ts          # Main server implementation
├── dist/                 # Compiled JavaScript output
├── package.json          # Project dependencies and scripts
├── tsconfig.json         # TypeScript configuration
├── README.md            # Project documentation
├── .env.example         # Environment variables template
├── Dockerfile           # Docker configuration for cloud deployment
├── docker-compose.yml   # Local Docker development setup
└── install.sh           # Setup script
```

## Core Implementation

### 1. Project Setup

#### package.json
```json
{
  "name": "mcp-weather-server",
  "version": "1.0.0",
  "description": "MCP server for weather data using external API - Cloud Ready",
  "main": "dist/index.js",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts",
    "start:cloud": "npm run build && node dist/index.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "node-fetch": "^3.3.2"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/express": "^4.17.17",
    "@types/cors": "^2.8.13",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0"
  },
  "bin": {
    "mcp-weather-server": "./dist/index.js"
  }
}
```

#### TypeScript Configuration (tsconfig.json)
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "node",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### 2. Main Server Implementation (src/index.ts)

```typescript
#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import express, { Request, Response } from "express";
import cors from "cors";

// Type definitions for better code quality
interface WeatherData {
  location: string;
  temperature: number;
  description: string;
  humidity: number;
  windSpeed: number;
  feelsLike: number;
}

interface WeatherApiResponse {
  main: {
    temp: number;
    feels_like: number;
    humidity: number;
  };
  weather: Array<{
    description: string;
  }>;
  wind: {
    speed: number;
  };
  name: string;
}

class WeatherServer {
  private server: Server;
  private apiKey: string;
  private app?: express.Application;
  private transports: Map<string, SSEServerTransport> = new Map();
  private deploymentMode: 'stdio' | 'cloud';

  constructor() {
    // Initialize the MCP server with metadata
    this.server = new Server(
      {
        name: "weather-server",
        version: "1.0.0",
      },
      {
        capabilities: {
          tools: {}, // Declare that this server provides tools
        },
      }
    );

    // Get API key from environment variables
    this.apiKey = process.env.OPENWEATHER_API_KEY || "";
    if (!this.apiKey) {
      console.error("OPENWEATHER_API_KEY environment variable is required");
      process.exit(1);
    }

    // Determine deployment mode
    this.deploymentMode = process.env.DEPLOYMENT_MODE === 'cloud' ? 'cloud' : 'stdio';
    
    if (this.deploymentMode === 'cloud') {
      this.setupExpress();
      this.setupRoutes();
    }

    this.setupToolHandlers();
  }

  private setupExpress() {
    // Initialize Express app for cloud deployment
    this.app = express();
    
    // Enable CORS for cloud deployment
    this.app.use(cors({
      origin: true, // Allow all origins in development
      credentials: true,
      methods: ['GET', 'POST', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'x-api-key', 'mcp-session-id']
    }));

    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true }));

    // Health check endpoint
    this.app.get('/health', (req: Request, res: Response) => {
      res.json({ 
        status: 'healthy', 
        service: 'mcp-weather-server',
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        mode: this.deploymentMode
      });
    });
  }

  private setupRoutes() {
    if (!this.app) return;

    // SSE connection endpoint
    this.app.get('/sse', this.handleSSEConnection.bind(this));
    
    // Message handling endpoint for SSE
    this.app.post('/messages', this.handleMessages.bind(this));

    // Alternative endpoint for direct MCP communication
    this.app.post('/mcp', this.handleDirectMCP.bind(this));
  }

  private async handleSSEConnection(req: Request, res: Response) {
    try {
      console.log('New SSE connection request');
      
      // PAT (Personal Access Token) authentication
      if (!this.authenticateRequest(req)) {
        res.status(401).json({ 
          error: 'Unauthorized', 
          message: 'Valid Personal Access Token required' 
        });
        return;
      }

      const transport = new SSEServerTransport("/messages", res);
      const sessionId = transport.sessionId;
      
      // Store transport for message handling
      this.transports.set(sessionId, transport);
      
      // Clean up on connection close
      res.on('close', () => {
        console.log(`SSE connection closed for session: ${sessionId}`);
        this.transports.delete(sessionId);
      });

      // Connect the MCP server to this transport
      await this.server.connect(transport);
      
      console.log(`SSE connection established with session: ${sessionId}`);
      
    } catch (error) {
      console.error('Error in SSE connection:', error);
      res.status(500).json({ error: 'Failed to establish SSE connection' });
    }
  }

  private async handleMessages(req: Request, res: Response) {
    try {
      // Authenticate for each message request
      if (!this.authenticateRequest(req)) {
        res.status(401).json({ 
          error: 'Unauthorized', 
          message: 'Valid Personal Access Token required' 
        });
        return;
      }

      const sessionId = req.query.sessionId as string;
      
      if (!sessionId) {
        res.status(400).json({ error: 'Session ID required' });
        return;
      }

      const transport = this.transports.get(sessionId);
      if (!transport) {
        res.status(404).json({ error: 'Session not found' });
        return;
      }

      // Handle the message through the transport
      await transport.handlePostMessage(req, res, req.body);
      
    } catch (error) {
      console.error('Error handling message:', error);
      res.status(500).json({ error: 'Failed to handle message' });
    }
  }

  private async handleDirectMCP(req: Request, res: Response) {
    try {
      // Authenticate for direct MCP requests
      if (!this.authenticateRequest(req)) {
        res.status(401).json({ 
          error: 'Unauthorized', 
          message: 'Valid Personal Access Token required' 
        });
        return;
      }

      // For direct MCP communication without SSE
      res.setHeader('Content-Type', 'application/json');
      
      // Create a temporary transport instance for this request
      const tempTransport = new SSEServerTransport("/mcp", res);
      await this.server.connect(tempTransport);
      await tempTransport.handlePostMessage(req, res, req.body);
      
    } catch (error) {
      console.error('Error in direct MCP handling:', error);
      res.status(500).json({ error: 'Failed to handle MCP request' });
    }
  }

  private authenticateRequest(req: Request): boolean {
    // Skip authentication if not required
    if (process.env.REQUIRE_AUTH !== 'true') {
      return true;
    }

    // Check for PAT in Authorization header (Bearer token format)
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.substring(7); // Remove 'Bearer ' prefix
      return this.validatePAT(token);
    }

    // Check for PAT in x-api-key header (legacy support)
    const apiKey = req.headers['x-api-key'] as string;
    if (apiKey) {
      return this.validatePAT(apiKey);
    }

    // Check for PAT in query parameter (least secure, but sometimes necessary)
    const tokenParam = req.query.token as string;
    if (tokenParam) {
      return this.validatePAT(tokenParam);
    }

    return false;
  }

  private validatePAT(token: string): boolean {
    if (!token) return false;

    // Validate against environment variable tokens
    const validTokens = this.getValidTokens();
    
    // Basic token validation
    if (validTokens.includes(token)) {
      return true;
    }

    // Advanced token validation (if using structured tokens)
    return this.validateStructuredPAT(token);
  }

  private getValidTokens(): string[] {
    // Support multiple token formats
    const apiKeys = process.env.API_KEYS?.split(',') || [];
    const patTokens = process.env.PAT_TOKENS?.split(',') || [];
    
    return [...apiKeys, ...patTokens].filter(token => token && token.trim().length > 0);
  }

  private validateStructuredPAT(token: string): boolean {
    try {
      // Example: validate JWT-like PAT tokens
      if (token.startsWith('mcp_') && token.length >= 32) {
        // Custom PAT format validation
        const parts = token.split('_');
        if (parts.length >= 3 && parts[0] === 'mcp') {
          // Validate token structure and checksum if needed
          return this.validateTokenChecksum(token);
        }
      }
      
      // Add more validation logic as needed
      return false;
    } catch (error) {
      console.error('Error validating structured PAT:', error);
      return false;
    }
  }

  private validateTokenChecksum(token: string): boolean {
    // Implement token checksum validation if using structured tokens
    // This is a placeholder - implement according to your token format
    return token.length >= 32;
  }

  private setupToolHandlers() {
    // Register handler for listing available tools
    this.server.setRequestHandler(ListToolsRequestSchema, async () => {
      return {
        tools: [
          {
            name: "get_current_weather",
            description: "Get current weather information for a specific location",
            inputSchema: {
              type: "object",
              properties: {
                location: {
                  type: "string",
                  description: "City name or location (e.g., 'London', 'New York, NY')",
                },
                units: {
                  type: "string",
                  enum: ["metric", "imperial", "kelvin"],
                  description: "Temperature units (metric=Celsius, imperial=Fahrenheit, kelvin=Kelvin)",
                  default: "metric",
                },
              },
              required: ["location"],
            },
          } as Tool,
          {
            name: "get_weather_forecast",
            description: "Get 5-day weather forecast for a specific location",
            inputSchema: {
              type: "object",
              properties: {
                location: {
                  type: "string",
                  description: "City name or location (e.g., 'London', 'New York, NY')",
                },
                units: {
                  type: "string",
                  enum: ["metric", "imperial", "kelvin"],
                  description: "Temperature units (metric=Celsius, imperial=Fahrenheit, kelvin=Kelvin)",
                  default: "metric",
                },
              },
              required: ["location"],
            },
          } as Tool,
        ],
      };
    });

    // Register handler for tool execution
    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;

      try {
        switch (name) {
          case "get_current_weather":
            return await this.getCurrentWeather(args);
          case "get_weather_forecast":
            return await this.getWeatherForecast(args);
          default:
            throw new Error(`Unknown tool: ${name}`);
        }
      } catch (error) {
        return {
          content: [
            {
              type: "text",
              text: `Error: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    });
  }

  // Implementation of current weather tool
  private async getCurrentWeather(args: any) {
    const { location, units = "metric" } = args;

    if (!location) {
      throw new Error("Location is required");
    }

    // Construct API URL
    const url = `https://api.openweathermap.org/data/2.5/weather?q=${encodeURIComponent(
      location
    )}&appid=${this.apiKey}&units=${units}`;

    // Make API request
    const response = await fetch(url);
    
    if (!response.ok) {
      if (response.status === 404) {
        throw new Error(`Location "${location}" not found`);
      }
      throw new Error(`Weather API error: ${response.status} ${response.statusText}`);
    }

    const data: WeatherApiResponse = await response.json();
    
    // Transform API response to our format
    const weatherData: WeatherData = {
      location: data.name,
      temperature: Math.round(data.main.temp),
      description: data.weather[0].description,
      humidity: data.main.humidity,
      windSpeed: data.wind.speed,
      feelsLike: Math.round(data.main.feels_like),
    };

    // Format response for display
    const unitsSymbol = units === "imperial" ? "°F" : units === "kelvin" ? "K" : "°C";
    const windUnits = units === "imperial" ? "mph" : "m/s";

    const weatherReport = `🌤️ Current Weather for ${weatherData.location}

🌡️ Temperature: ${weatherData.temperature}${unitsSymbol} (feels like ${weatherData.feelsLike}${unitsSymbol})
📝 Conditions: ${weatherData.description}
💧 Humidity: ${weatherData.humidity}%
💨 Wind Speed: ${weatherData.windSpeed} ${windUnits}`;

    return {
      content: [
        {
          type: "text",
          text: weatherReport,
        },
      ],
    };
  }

  // Implementation of weather forecast tool
  private async getWeatherForecast(args: any) {
    const { location, units = "metric" } = args;

    if (!location) {
      throw new Error("Location is required");
    }

    const url = `https://api.openweathermap.org/data/2.5/forecast?q=${encodeURIComponent(
      location
    )}&appid=${this.apiKey}&units=${units}`;

    const response = await fetch(url);
    
    if (!response.ok) {
      if (response.status === 404) {
        throw new Error(`Location "${location}" not found`);
      }
      throw new Error(`Weather API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    
    const unitsSymbol = units === "imperial" ? "°F" : units === "kelvin" ? "K" : "°C";
    
    let forecastReport = `🌤️ 5-Day Weather Forecast for ${data.city.name}\n\n`;
    
    // Process forecast data (API returns 3-hour intervals)
    const dailyForecasts = new Map();
    
    data.list.forEach((item: any) => {
      const date = new Date(item.dt * 1000);
      const dateKey = date.toDateString();
      
      if (!dailyForecasts.has(dateKey)) {
        dailyForecasts.set(dateKey, {
          date: dateKey,
          temps: [],
          descriptions: [],
          humidity: item.main.humidity,
          windSpeed: item.wind.speed,
        });
      }
      
      dailyForecasts.get(dateKey).temps.push(item.main.temp);
      dailyForecasts.get(dateKey).descriptions.push(item.weather[0].description);
    });

    // Format each day's forecast
    Array.from(dailyForecasts.values()).slice(0, 5).forEach((day: any) => {
      const minTemp = Math.round(Math.min(...day.temps));
      const maxTemp = Math.round(Math.max(...day.temps));
      const mostCommonDesc = day.descriptions[0];
      
      forecastReport += `📅 ${day.date}
🌡️ ${minTemp}${unitsSymbol} - ${maxTemp}${unitsSymbol}
📝 ${mostCommonDesc}
💧 Humidity: ${day.humidity}%

`;
    });

    return {
      content: [
        {
          type: "text",
          text: forecastReport,
        },
      ],
    };
  }

  // Start the server based on deployment mode
  async run() {
    if (this.deploymentMode === 'cloud') {
      // Cloud deployment with HTTP server
      const port = process.env.PORT || 3000;
      
      if (!this.app) {
        throw new Error("Express app not initialized");
      }

      this.app.listen(port, '0.0.0.0', () => {
        console.log(`🌤️ Weather MCP Server running on port ${port}`);
        console.log(`SSE endpoint: http://localhost:${port}/sse`);
        console.log(`Health check: http://localhost:${port}/health`);
        console.log(`Direct MCP: http://localhost:${port}/mcp`);
      });
    } else {
      // Local deployment with stdio transport
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("Weather MCP server running on stdio");
    }
  }
}

// Initialize and start the server
const server = new WeatherServer();
server.run().catch((error) => {
  console.error("Server error:", error);
  process.exit(1);
});
```

## Key Implementation Concepts

### 1. Dual Transport Support
The server now supports both transport modes:
- **stdio**: For local integrations (default)
- **cloud**: For cloud deployment with SSE transport

### 2. Server Initialization
- Create a `Server` instance with metadata (name, version)
- Declare capabilities (in this case, `tools`)
- Set up request handlers for different operations
- Configure transport based on deployment mode

### 3. Tool Registration
Use `ListToolsRequestSchema` to register available tools with:
- **name**: Unique identifier for the tool
- **description**: What the tool does
- **inputSchema**: JSON Schema defining expected parameters

### 4. Tool Execution
Use `CallToolRequestSchema` to handle tool invocations:
- Extract tool name and arguments from request
- Route to appropriate handler method
- Return formatted response or error

### 5. External API Integration
- Use environment variables for API keys
- Implement proper error handling for API failures
- Transform API responses to user-friendly formats
- Handle rate limits and authentication

### 6. Cloud Deployment Features
- **Express HTTP Server**: Handles HTTP requests for SSE transport
- **CORS Support**: Enables cross-origin requests
- **Session Management**: Manages multiple concurrent connections
- **Health Checks**: Monitoring endpoints for cloud platforms
- **Optional Authentication**: API key validation for secure access

### 7. Error Handling
```typescript
try {
  // API call logic
} catch (error) {
  return {
    content: [{
      type: "text",
      text: `Error: ${error instanceof Error ? error.message : String(error)}`,
    }],
    isError: true,
  };
}
```

## Environment Configuration

### Environment Variables (.env.example)
```bash
# Required: OpenWeatherMap API key
OPENWEATHER_API_KEY=your_openweathermap_api_key_here

# Deployment mode: 'stdio' (default) or 'cloud'
DEPLOYMENT_MODE=stdio

# Cloud deployment settings
PORT=3000

# Authentication settings
REQUIRE_AUTH=true

# PAT (Personal Access Token) authentication - Choose one or both methods:

# Method 1: Simple API keys (legacy support)
API_KEYS=key1,key2,key3

# Method 2: Structured PAT tokens (recommended for production)
PAT_TOKENS=mcp_dev_1234567890abcdef1234567890abcdef,mcp_prod_fedcba0987654321fedcba0987654321

# Example structured PAT format: mcp_{environment}_{32-char-hex}
# mcp_dev_1234567890abcdef1234567890abcdef
# mcp_prod_fedcba0987654321fedcba0987654321
# mcp_staging_abcdef1234567890abcdef1234567890
```

## PAT (Personal Access Token) Authorization

### Overview
Personal Access Tokens provide a secure way to authenticate clients with your MCP server in cloud deployments. PATs offer several advantages over simple API keys:

- **Structured format**: Easy to identify and manage
- **Environment-specific**: Different tokens for dev/staging/prod
- **Revocable**: Individual tokens can be disabled
- **Auditable**: Track usage by specific tokens
- **Secure**: Can include checksums and expiration

### Token Formats Supported

#### 1. Simple API Keys (Legacy)
```bash
# Environment variable
API_KEYS=simple-key-1,simple-key-2,another-key

# Client usage
Authorization: Bearer simple-key-1
# or
x-api-key: simple-key-1
```

#### 2. Structured PAT Tokens (Recommended)
```bash
# Format: mcp_{environment}_{32-character-hex}
PAT_TOKENS=mcp_dev_1234567890abcdef1234567890abcdef,mcp_prod_fedcba0987654321fedcba0987654321

# Client usage
Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef
```

### Generating PAT Tokens

#### Manual Generation
```bash
# Generate a random 32-character hex token
openssl rand -hex 16

# Create structured PAT
echo "mcp_dev_$(openssl rand -hex 16)"
echo "mcp_prod_$(openssl rand -hex 16)"
```

#### Programmatic Generation (Node.js)
```javascript
const crypto = require('crypto');

function generatePAT(environment = 'dev') {
  const randomHex = crypto.randomBytes(16).toString('hex');
  return `mcp_${environment}_${randomHex}`;
}

// Usage
console.log(generatePAT('dev'));     // mcp_dev_a1b2c3d4e5f6789012345678901234ab
console.log(generatePAT('prod'));    // mcp_prod_f1e2d3c4b5a6987654321098765432cd
console.log(generatePAT('staging')); // mcp_staging_1a2b3c4d5e6f789012345678901234ef
```

#### Advanced Token Generation Script
```javascript
#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');

class PATGenerator {
  static generateToken(environment, userId = null) {
    const timestamp = Math.floor(Date.now() / 1000).toString(16);
    const randomBytes = crypto.randomBytes(12).toString('hex');
    const userPart = userId ? `_${userId}` : '';
    
    return `mcp_${environment}${userPart}_${timestamp}_${randomBytes}`;
  }

  static generateMultiple(environments, count = 1) {
    const tokens = {};
    
    environments.forEach(env => {
      tokens[env] = [];
      for (let i = 0; i < count; i++) {
        tokens[env].push(this.generateToken(env));
      }
    });
    
    return tokens;
  }

  static saveToEnvFile(tokens, filename = '.env.tokens') {
    const envContent = Object.entries(tokens)
      .map(([env, tokenList]) => `${env.toUpperCase()}_TOKENS=${tokenList.join(',')}`)
      .join('\n');
    
    fs.writeFileSync(filename, envContent);
    console.log(`Tokens saved to ${filename}`);
  }
}

// Generate tokens for different environments
const tokens = PATGenerator.generateMultiple(['dev', 'staging', 'prod'], 2);
console.log('Generated PAT tokens:', tokens);

// Save to file
PATGenerator.saveToEnvFile(tokens);
```

### Authentication Methods

The server supports multiple authentication methods in order of security preference:

#### 1. Authorization Header (Bearer Token) - **Recommended**
```bash
curl -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
     https://your-domain.com/sse
```

#### 2. x-api-key Header (Legacy Support)
```bash
curl -H "x-api-key: mcp_dev_1234567890abcdef1234567890abcdef" \
     https://your-domain.com/sse
```

#### 3. Query Parameter (Least Secure)
```bash
curl "https://your-domain.com/sse?token=mcp_dev_1234567890abcdef1234567890abcdef"
```

### Security Configuration

#### Development Environment
```bash
REQUIRE_AUTH=false  # Optional for local development
# or
REQUIRE_AUTH=true
PAT_TOKENS=mcp_dev_1234567890abcdef1234567890abcdef
```

#### Staging Environment
```bash
REQUIRE_AUTH=true
PAT_TOKENS=mcp_staging_abcdef1234567890abcdef1234567890,mcp_staging_fedcba0987654321fedcba0987654321
```

#### Production Environment
```bash
REQUIRE_AUTH=true
PAT_TOKENS=mcp_prod_a1b2c3d4e5f6789012345678901234ab,mcp_prod_f1e2d3c4b5a6987654321098765432cd
# Never use dev/staging tokens in production
```

## Setup and Usage

### 1. Installation
```bash
# Install dependencies
npm install

# Build the project
npm run build
```

### 2. Local Development (stdio)
```bash
# Set environment variables
export OPENWEATHER_API_KEY=your_api_key_here

# Run in development mode
npm run dev

# Or production mode
npm start
```

### 3. Cloud Deployment
```bash
# Set environment variables for cloud mode
export OPENWEATHER_API_KEY=your_api_key_here
export DEPLOYMENT_MODE=cloud
export PORT=3000

# Build and start
npm run start:cloud
```

## Cloud Deployment Options

### 1. Docker Deployment

#### Dockerfile
```dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Start the server
CMD ["npm", "start"]
```

#### Docker Commands
```bash
# Build image
docker build -t weather-mcp-server .

# Run container
docker run -p 3000:3000 \
  -e OPENWEATHER_API_KEY=your_key \
  -e DEPLOYMENT_MODE=cloud \
  weather-mcp-server
```

### 2. Cloud Platform Deployments

#### Azure Container Apps
```bash
az containerapp up \
  -g myResourceGroup \
  -n weather-mcp \
  --environment myEnv \
  --env-vars OPENWEATHER_API_KEY=your_key DEPLOYMENT_MODE=cloud \
  --source .
```

#### Google Cloud Run
```bash
gcloud run deploy weather-mcp \
  --source . \
  --set-env-vars OPENWEATHER_API_KEY=your_key,DEPLOYMENT_MODE=cloud \
  --platform managed
```

#### AWS App Runner / ECS
```bash
# Using AWS Copilot
copilot app init weather-mcp
copilot env init --name production
copilot svc init --name api
# Configure environment variables in copilot/api/manifest.yml
copilot svc deploy --name api --env production
```

### 3. Docker Compose for Development
```yaml
version: '3.8'

services:
  weather-mcp:
    build: .
    ports:
      - "3000:3000"
    environment:
      - OPENWEATHER_API_KEY=${OPENWEATHER_API_KEY}
      - DEPLOYMENT_MODE=cloud
      - PORT=3000
      - REQUIRE_AUTH=false
    restart: unless-stopped
```

## Integration Examples

### 1. Local Integration (stdio)
Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "weather": {
      "command": "node",
      "args": ["/path/to/your/project/dist/index.js"],
      "env": {
        "OPENWEATHER_API_KEY": "your_api_key_here",
        "DEPLOYMENT_MODE": "stdio"
      }
    }
  }
}
```

### 2. Cloud Integration (SSE with PAT)
Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "weather": {
      "type": "sse",
      "url": "https://your-domain.com/sse",
      "headers": {
        "Authorization": "Bearer mcp_prod_a1b2c3d4e5f6789012345678901234ab"
      }
    }
  }
}
```

### 3. Cloud Integration (Legacy API Key)
Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "weather": {
      "type": "sse",
      "url": "https://your-domain.com/sse",
      "headers": {
        "x-api-key": "your-legacy-api-key"
      }
    }
  }
}
```

### 4. VS Code Integration with PAT
In VS Code, run the `MCP: Add server` command and configure:
```json
{
  "inputs": [
    {
      "type": "promptString",
      "id": "weather-pat-token",
      "description": "Weather MCP Personal Access Token",
      "password": true
    }
  ],
  "servers": {
    "weather-cloud": {
      "type": "sse",
      "url": "https://your-domain.com/sse",
      "headers": {
        "Authorization": "Bearer ${input:weather-pat-token}"
      }
    }
  }
}
```

### 5. Programmatic Client Example
```typescript
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";

// Create client with PAT authentication
const client = new Client({
  name: "weather-client",
  version: "1.0.0"
});

const transport = new SSEClientTransport(
  new URL("https://your-domain.com/sse"),
  {
    headers: {
      "Authorization": "Bearer mcp_prod_a1b2c3d4e5f6789012345678901234ab"
    }
  }
);

await client.connect(transport);

// Use the client
const tools = await client.listTools();
console.log("Available tools:", tools);
```

### 6. Multiple Environment Configuration
```json
{
  "inputs": [
    {
      "type": "pickString",
      "id": "environment",
      "description": "Select Environment",
      "options": [
        { "label": "Development", "value": "dev" },
        { "label": "Staging", "value": "staging" },
        { "label": "Production", "value": "prod" }
      ]
    },
    {
      "type": "promptString",
      "id": "weather-pat-token",
      "description": "Personal Access Token",
      "password": true
    }
  ],
  "servers": {
    "weather-dev": {
      "type": "sse",
      "url": "https://dev-weather-mcp.your-domain.com/sse",
      "headers": {
        "Authorization": "Bearer ${input:weather-pat-token}"
      },
      "when": "${input:environment} == 'dev'"
    },
    "weather-staging": {
      "type": "sse", 
      "url": "https://staging-weather-mcp.your-domain.com/sse",
      "headers": {
        "Authorization": "Bearer ${input:weather-pat-token}"
      },
      "when": "${input:environment} == 'staging'"
    },
    "weather-prod": {
      "type": "sse",
      "url": "https://weather-mcp.your-domain.com/sse", 
      "headers": {
        "Authorization": "Bearer ${input:weather-pat-token}"
      },
      "when": "${input:environment} == 'prod'"
    }
  }
}
```

## PAT Security Best Practices

### 1. Token Management
- **Rotate tokens regularly**: Generate new tokens every 90 days
- **Use environment-specific tokens**: Never use production tokens in development
- **Implement token expiration**: Add timestamp validation for enhanced security
- **Store securely**: Use secure secret management systems
- **Audit token usage**: Log and monitor token access

### 2. Token Storage
```bash
# ✅ Good: Use environment variables
export PAT_TOKENS=mcp_prod_a1b2c3d4e5f6789012345678901234ab

# ✅ Good: Use secret management services
# AWS Secrets Manager, Azure Key Vault, Google Secret Manager

# ❌ Bad: Never store in code
const token = "mcp_prod_a1b2c3d4e5f6789012345678901234ab"; // DON'T DO THIS

# ❌ Bad: Never commit to version control
# .env files with real tokens should be in .gitignore
```

### 3. Token Scope and Permissions
```typescript
// Example: Enhanced token validation with permissions
interface PATInfo {
  environment: string;
  permissions: string[];
  userId?: string;
  expiresAt?: number;
  createdAt: number;
}

class EnhancedPATValidator {
  static parsePAT(token: string): PATInfo | null {
    // Parse structured PAT: mcp_{env}_{user}_{timestamp}_{random}
    const parts = token.split('_');
    if (parts.length < 4 || parts[0] !== 'mcp') return null;
    
    const [, environment, userOrTimestamp, ...rest] = parts;
    
    // Determine if user is included
    const hasUser = rest.length > 1;
    const userId = hasUser ? userOrTimestamp : undefined;
    const timestamp = hasUser ? parseInt(rest[0], 16) : parseInt(userOrTimestamp, 16);
    
    return {
      environment,
      userId,
      createdAt: timestamp,
      permissions: this.getPermissionsForEnvironment(environment),
      expiresAt: timestamp + (90 * 24 * 60 * 60) // 90 days expiration
    };
  }
  
  static validateToken(token: string): boolean {
    const info = this.parsePAT(token);
    if (!info) return false;
    
    // Check expiration
    if (info.expiresAt && Date.now() / 1000 > info.expiresAt) {
      console.log(`Token expired: ${token.substring(0, 10)}...`);
      return false;
    }
    
    return true;
  }
  
  static getPermissionsForEnvironment(env: string): string[] {
    const permissionMap = {
      'dev': ['read', 'write', 'debug'],
      'staging': ['read', 'write'],
      'prod': ['read']
    };
    
    return permissionMap[env] || [];
  }
}
```

### 4. Rate Limiting and Monitoring
```typescript
// Example: Token-based rate limiting
class TokenRateLimiter {
  private static tokenUsage = new Map<string, { count: number; resetTime: number }>();
  
  static checkRateLimit(token: string, maxRequests = 100, windowMs = 60000): boolean {
    const now = Date.now();
    const tokenHash = this.hashToken(token);
    
    const usage = this.tokenUsage.get(tokenHash) || { count: 0, resetTime: now + windowMs };
    
    if (now > usage.resetTime) {
      usage.count = 0;
      usage.resetTime = now + windowMs;
    }
    
    if (usage.count >= maxRequests) {
      return false; // Rate limit exceeded
    }
    
    usage.count++;
    this.tokenUsage.set(tokenHash, usage);
    return true;
  }
  
  private static hashToken(token: string): string {
    // Hash token for privacy in logs
    const crypto = require('crypto');
    return crypto.createHash('sha256').update(token).digest('hex').substring(0, 16);
  }
}
```

### 5. Cloud Deployment
- Use health checks for monitoring
- Implement proper logging
- Set resource limits appropriately
- Use environment-specific configurations
- Enable CORS for web client access
- **Implement PAT authentication for production**
- **Rotate tokens regularly and audit access**
- **Use HTTPS only for cloud deployments**

### 6. User Experience
- Format responses for readability
- Use emojis and clear formatting
- Provide helpful error messages
- Support different units/formats

## Security Considerations

### 1. Authentication and Authorization

#### PAT (Personal Access Token) Security
- **Token Format**: Use structured tokens with environment identifiers
- **Token Storage**: Store in secure secret management systems
- **Token Rotation**: Implement regular rotation (90-day maximum)
- **Token Scope**: Limit permissions based on environment
- **Token Audit**: Log and monitor all token usage

```typescript
// Example: Secure token handling
class SecurePATHandler {
  static validateTokenSecurity(token: string): SecurityResult {
    const checks = {
      format: /^mcp_[a-z]+_[a-f0-9]{32}$/.test(token),
      length: token.length >= 40,
      environment: ['dev', 'staging', 'prod'].includes(token.split('_')[1]),
      entropy: this.calculateEntropy(token.split('_')[2])
    };
    
    return {
      isSecure: Object.values(checks).every(Boolean),
      checks,
      recommendations: this.getSecurityRecommendations(checks)
    };
  }
  
  static logTokenUsage(token: string, action: string, clientInfo: any) {
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex').substring(0, 16);
    
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      tokenHash,
      action,
      clientInfo: {
        ip: clientInfo.ip,
        userAgent: clientInfo.userAgent,
        origin: clientInfo.origin
      }
    }));
  }
}
```

#### Multi-Factor Authentication (Optional)
```typescript
// Example: Enhanced authentication with multiple factors
class MFAHandler {
  static async validateMFA(req: Request): Promise<boolean> {
    const token = this.extractToken(req);
    const clientCert = req.headers['x-client-cert'];
    const ipWhitelist = process.env.IP_WHITELIST?.split(',') || [];
    
    // Validate PAT
    if (!this.validatePAT(token)) return false;
    
    // Validate client certificate (if required)
    if (process.env.REQUIRE_CLIENT_CERT === 'true' && !clientCert) {
      return false;
    }
    
    // Validate IP whitelist (if configured)
    if (ipWhitelist.length > 0) {
      const clientIP = req.ip || req.connection.remoteAddress;
      if (!ipWhitelist.includes(clientIP)) return false;
    }
    
    return true;
  }
}
```

### 2. Data Security

#### Encryption and Transport Security
- **HTTPS Only**: Never use HTTP for cloud deployments
- **TLS 1.3**: Use modern TLS versions
- **Certificate Validation**: Implement proper cert validation
- **HSTS Headers**: Enable HTTP Strict Transport Security

```nginx
# Example: Nginx SSL configuration
server {
    listen 443 ssl http2;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    ssl_protocols TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        proxy_pass http://mcp-server:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Data Validation and Sanitization
```typescript
// Example: Input validation and sanitization
class InputValidator {
  static validateWeatherRequest(args: any): ValidationResult {
    const errors: string[] = [];
    
    // Validate location
    if (!args.location || typeof args.location !== 'string') {
      errors.push('Location must be a non-empty string');
    } else if (args.location.length > 100) {
      errors.push('Location must be less than 100 characters');
    } else if (!/^[a-zA-Z0-9\s,.-]+$/.test(args.location)) {
      errors.push('Location contains invalid characters');
    }
    
    // Validate units
    if (args.units && !['metric', 'imperial', 'kelvin'].includes(args.units)) {
      errors.push('Units must be metric, imperial, or kelvin');
    }
    
    return {
      isValid: errors.length === 0,
      errors,
      sanitizedArgs: {
        location: this.sanitizeString(args.location),
        units: args.units || 'metric'
      }
    };
  }
  
  static sanitizeString(input: string): string {
    return input
      .trim()
      .replace(/[<>]/g, '') // Remove potential HTML
      .substring(0, 100);   // Limit length
  }
}
```

### 3. Network Security

#### Rate Limiting and DDoS Protection
```typescript
// Example: Advanced rate limiting
class AdvancedRateLimiter {
  private static limits = new Map<string, RateLimit>();
  
  static checkLimits(req: Request): RateLimitResult {
    const token = this.extractToken(req);
    const ip = req.ip;
    
    // Different limits for different entities
    const tokenLimit = this.checkTokenLimit(token, 100, 60000); // 100 req/min per token
    const ipLimit = this.checkIPLimit(ip, 200, 60000);         // 200 req/min per IP
    const globalLimit = this.checkGlobalLimit(1000, 60000);    // 1000 req/min globally
    
    return {
      allowed: tokenLimit.allowed && ipLimit.allowed && globalLimit.allowed,
      limits: { token: tokenLimit, ip: ipLimit, global: globalLimit }
    };
  }
  
  static implementCircuitBreaker(errorRate: number, threshold = 0.5): boolean {
    // Implement circuit breaker pattern for external API calls
    return errorRate < threshold;
  }
}
```

#### CORS and Origin Validation
```typescript
// Example: Secure CORS configuration
const corsOptions = {
  origin: (origin, callback) => {
    const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || [];
    
    // Allow requests with no origin (mobile apps, etc.)
    if (!origin) return callback(null, true);
    
    if (allowedOrigins.includes(origin) || process.env.NODE_ENV === 'development') {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  optionsSuccessStatus: 200,
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-api-key'],
  exposedHeaders: ['X-RateLimit-Remaining', 'X-RateLimit-Reset']
};
```

### 4. Monitoring and Auditing

#### Security Event Logging
```typescript
// Example: Comprehensive security logging
class SecurityLogger {
  static logSecurityEvent(event: SecurityEvent) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      eventType: event.type,
      severity: event.severity,
      details: {
        tokenHash: event.tokenHash,
        clientIP: event.clientIP,
        userAgent: event.userAgent,
        action: event.action,
        result: event.result
      },
      metadata: {
        sessionId: event.sessionId,
        requestId: event.requestId,
        environment: process.env.NODE_ENV
      }
    };
    
    // Send to logging service (e.g., ELK, Splunk, CloudWatch)
    console.log(JSON.stringify(logEntry));
    
    // Alert on critical events
    if (event.severity === 'critical') {
      this.sendAlert(logEntry);
    }
  }
  
  static sendAlert(logEntry: any) {
    // Implement alerting mechanism (e.g., PagerDuty, Slack, email)
  }
}

// Usage examples
SecurityLogger.logSecurityEvent({
  type: 'authentication_failure',
  severity: 'warning',
  tokenHash: 'abc123...',
  clientIP: '192.168.1.1',
  action: 'sse_connection',
  result: 'denied'
});
```

#### Health and Performance Monitoring
```typescript
// Example: Advanced health checks
class HealthMonitor {
  static async performHealthCheck(): Promise<HealthStatus> {
    const checks = await Promise.all([
      this.checkExternalAPI(),
      this.checkDatabase(),
      this.checkMemoryUsage(),
      this.checkTokenValidation(),
      this.checkRateLimit()
    ]);
    
    const overallHealth = checks.every(check => check.status === 'healthy') 
      ? 'healthy' 
      : 'unhealthy';
    
    return {
      status: overallHealth,
      timestamp: new Date().toISOString(),
      checks: checks.reduce((acc, check) => {
        acc[check.name] = check;
        return acc;
      }, {}),
      version: process.env.npm_package_version
    };
  }
}
```

### 5. Production Deployment Security Checklist

```bash
# Pre-deployment security checklist

# ✅ Authentication
export REQUIRE_AUTH=true
export PAT_TOKENS="production-tokens-only"

# ✅ HTTPS/TLS
# - Valid SSL certificate installed
# - TLS 1.3 enabled
# - HSTS headers configured

# ✅ Environment Security
export NODE_ENV=production
export DEBUG=""  # Disable debug logging
unset API_KEYS   # Remove any test keys

# ✅ Network Security
export ALLOWED_ORIGINS="https://your-app.com,https://trusted-domain.com"
export IP_WHITELIST="10.0.0.0/8,172.16.0.0/12"  # If using IP restrictions

# ✅ Resource Limits
# - Container memory limits set
# - CPU limits configured
# - Disk space monitoring enabled

# ✅ Monitoring
# - Health check endpoints configured
# - Error tracking enabled (Sentry, Rollbar)
# - Performance monitoring (New Relic, DataDog)
# - Security event logging

# ✅ Backup and Recovery
# - Configuration backups
# - Token rotation procedures
# - Incident response plan
```

## Transport Comparison

| Feature | stdio Transport | SSE Transport |
|---------|----------------|---------------|
| **Deployment** | Local only | Local or Cloud |
| **Scalability** | Single client | Multiple clients |
| **Performance** | Lower latency | Higher latency |
| **Setup** | Simpler | More complex |
| **Security** | Process isolation | HTTP authentication |
| **Dependencies** | None | Express, CORS |
| **Use Case** | Desktop apps | Web services |

## Best Practices

### 1. Type Safety
- Define TypeScript interfaces for API responses
- Use proper typing for function parameters
- Leverage the MCP SDK types

### 2. Error Handling
- Validate input parameters
- Handle API errors gracefully
- Provide meaningful error messages
- Use appropriate HTTP status codes

### 3. Security
- Store API keys in environment variables
- Validate and sanitize user inputs
- Implement rate limiting if needed
- Use HTTPS for API calls
- Enable authentication for cloud deployments

### 4. Performance
- Implement caching for frequently requested data
- Use appropriate HTTP timeout settings
- Handle API rate limits properly
- Monitor resource usage in cloud deployments

### 5. Cloud Deployment
- Use health checks for monitoring
- Implement proper logging
- Set resource limits appropriately
- Use environment-specific configurations
- Enable CORS for web client access
- **Implement PAT authentication for production**
- **Rotate tokens regularly and audit access**
- **Use HTTPS only for cloud deployments**

### 6. User Experience
- Format responses for readability
- Use emojis and clear formatting
- Provide helpful error messages
- Support different units/formats

## Monitoring and Debugging

### 1. Health Checks
The server provides a health endpoint at `/health`:
```bash
curl https://your-domain.com/health
```

### 2. Logging
Enable debug logging:
```bash
export DEBUG=mcp:*
npm start
```

### 3. Testing Cloud Endpoints
```bash
# Test SSE connection with PAT authentication
curl -H "Accept: text/event-stream" \
     -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
     https://your-domain.com/sse

# Test SSE connection with legacy API key
curl -H "Accept: text/event-stream" \
     -H "x-api-key: your-legacy-api-key" \
     https://your-domain.com/sse

# Test direct MCP with PAT
curl -X POST https://your-domain.com/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'

# Test authentication failure
curl -X POST https://your-domain.com/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer invalid-token" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'

# Expected response for authentication failure:
# {
#   "error": "Unauthorized",
#   "message": "Valid Personal Access Token required"
# }
```

### 4. PAT Token Testing
```bash
# Generate test tokens
node -e "
const crypto = require('crypto');
const generatePAT = (env) => \`mcp_\${env}_\${crypto.randomBytes(16).toString('hex')}\`;
console.log('Dev token:', generatePAT('dev'));
console.log('Prod token:', generatePAT('prod'));
"

# Test token validation
node -e "
const token = 'mcp_dev_1234567890abcdef1234567890abcdef';
console.log('Token format valid:', /^mcp_[a-z]+_[a-f0-9]{32}$/.test(token));
console.log('Environment:', token.split('_')[1]);
console.log('Token hash:', token.split('_')[2]);
"

# Validate token structure in server logs
curl -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
     https://your-domain.com/health
```

### 5. Security Testing
```bash
# Test rate limiting (if implemented)
for i in {1..10}; do
  curl -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
       https://your-domain.com/health
done

# Test token in different locations
# Authorization header (recommended)
curl -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
     https://your-domain.com/sse

# x-api-key header (legacy)
curl -H "x-api-key: mcp_dev_1234567890abcdef1234567890abcdef" \
     https://your-domain.com/sse

# Query parameter (least secure)
curl "https://your-domain.com/sse?token=mcp_dev_1234567890abcdef1234567890abcdef"

# Test CORS headers
curl -H "Origin: https://example.com" \
     -H "Authorization: Bearer mcp_dev_1234567890abcdef1234567890abcdef" \
     https://your-domain.com/sse
```

## Extension Ideas

1. **Weather Alerts**: Add severe weather notifications
2. **Historical Data**: Provide past weather information
3. **Air Quality**: Integrate air quality APIs
4. **Multiple Providers**: Support different weather services
5. **Caching**: Implement Redis caching for better performance
6. **Webhooks**: Real-time weather updates
7. **Location Services**: GPS coordinate support
8. **Multi-tenancy**: Support multiple API keys/users
9. **Rate Limiting**: Implement request throttling
10. **Analytics**: Track usage and performance metrics

## Testing

### Manual Testing
```bash
# Test stdio mode
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | npm start

# Test cloud mode
npm run start:cloud
# Then test with curl or web browser
```

### With Claude Desktop
Ask questions like:
- "What's the weather in London?"
- "Get me the forecast for Tokyo"
- "What's the temperature in New York in Fahrenheit?"

This implementation demonstrates the core concepts of building MCP servers with external API integration, supporting both local and cloud deployments for maximum flexibility and scalability.
