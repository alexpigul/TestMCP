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

interface ForecastApiResponse {
  city: {
    name: string;
  };
  list: Array<{
    dt: number;
    main: {
      temp: number;
      humidity: number;
    };
    weather: Array<{
      description: string;
    }>;
    wind: {
      speed: number;
    };
  }>;
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

    // Enable CORS
    this.app.use(cors());

    // Parse JSON bodies
    this.app.use(express.json());

    // Health check endpoint
    this.app.get("/health", (_, res) => {
      res.json({ status: "ok" });
    });

    // SSE endpoint
    this.app.get("/sse", (req, res) => {
      console.log("New SSE connection request");
      const transport = new SSEServerTransport("/sse", res);
      this.server.connect(transport).catch((error) => {
        console.error("Error connecting SSE transport:", error);
      });
    });

    // Direct MCP endpoint
    this.app.post("/mcp", (req, res) => {
      this.handleDirectMCP(req, res).catch((error) => {
        console.error("Error in direct MCP handling:", error);
        if (!res.headersSent) {
          res.status(500).json({ error: "Failed to handle MCP request" });
        }
      });
    });
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
        console.log('SSE connection closed for session:', sessionId);
        this.transports.delete(sessionId);
      });

      // Connect the MCP server to this transport
      await this.server.connect(transport);
      
      console.log('SSE connection established with session:', sessionId);
      
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

      // Process the request
      const { method, params } = req.body;
      
      if (!method) {
        res.status(400).json({ error: 'Method is required' });
        return;
      }

      // Handle the request based on method
      if (method === 'tools/list') {
        const response = await this.listTools();
        res.json({ jsonrpc: '2.0', id: req.body.id, result: response });
      } else if (method === 'tools/call' && params) {
        const response = await this.callTool(params);
        res.json({ jsonrpc: '2.0', id: req.body.id, result: response });
      } else {
        res.status(400).json({ error: 'Unknown method' });
      }
      
    } catch (error) {
      console.error('Error in direct MCP handling:', error);
      if (!res.headersSent) {
        res.status(500).json({ error: 'Failed to handle MCP request' });
      }
    }
  }

  private async listTools() {
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
  }

  private async callTool(params: any) {
    const { name, arguments: args } = params;

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
      // Example: validate PAT tokens with mcp_ prefix
      if (token.startsWith('mcp_') && token.length >= 32) {
        // Custom PAT format validation
        const parts = token.split('_');
        if (parts.length >= 3 && parts[0] === 'mcp') {
          // Validate token structure and checksum if needed
          return this.validateTokenChecksum(token);
        }
      }
      
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
            throw new Error("Unknown tool: " + name);
        }
      } catch (error) {
        return {
          content: [
            {
              type: "text",
              text: "Error: " + (error instanceof Error ? error.message : String(error)),
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
    const url = "https://api.openweathermap.org/data/2.5/weather?q=" + 
      encodeURIComponent(location) + "&appid=" + this.apiKey + "&units=" + units;

    // Make API request
    const response = await fetch(url);
    
    if (!response.ok) {
      if (response.status === 404) {
        throw new Error("Location \"" + location + "\" not found");
      }
      throw new Error("Weather API error: " + response.status + " " + response.statusText);
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

    const weatherReport = "🌤️ Current Weather for " + weatherData.location + "\n\n" +
      "🌡️ Temperature: " + weatherData.temperature + unitsSymbol + 
      " (feels like " + weatherData.feelsLike + unitsSymbol + ")\n" +
      "📝 Conditions: " + weatherData.description + "\n" +
      "💧 Humidity: " + weatherData.humidity + "%\n" +
      "💨 Wind Speed: " + weatherData.windSpeed + " " + windUnits;

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

    const url = "https://api.openweathermap.org/data/2.5/forecast?q=" + 
      encodeURIComponent(location) + "&appid=" + this.apiKey + "&units=" + units;

    const response = await fetch(url);
    
    if (!response.ok) {
      if (response.status === 404) {
        throw new Error("Location \"" + location + "\" not found");
      }
      throw new Error("Weather API error: " + response.status + " " + response.statusText);
    }

    const data: ForecastApiResponse = await response.json();
    
    const unitsSymbol = units === "imperial" ? "°F" : units === "kelvin" ? "K" : "°C";
    
    let forecastReport = "🌤️ 5-Day Weather Forecast for " + data.city.name + "\n\n";
    
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
      
      forecastReport += "📅 " + day.date + "\n" +
        "🌡️ " + minTemp + unitsSymbol + " - " + maxTemp + unitsSymbol + "\n" +
        "📝 " + mostCommonDesc + "\n" +
        "💧 Humidity: " + day.humidity + "%\n\n";
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
      const port = parseInt(process.env.PORT || '3000', 10);
      
      if (!this.app) {
        throw new Error("Express app not initialized");
      }

      this.app.listen(port, '0.0.0.0', () => {
        console.log("🌤️ Weather MCP Server running on port " + port);
        console.log("SSE endpoint: http://localhost:" + port + "/sse");
        console.log("Health check: http://localhost:" + port + "/health");
        console.log("Direct MCP: http://localhost:" + port + "/mcp");
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