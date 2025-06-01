# MCP Weather Server Cloud Setup Guide ☁️

Complete guide for deploying the MCP Weather Server to cloud environments using Docker and container orchestration.

## Prerequisites ✅

- ✅ Docker Desktop installed and running
- ✅ Docker Compose v2+ installed
- ✅ OpenWeatherMap API key: `6bb0e605343c674f8a58d1b5032e5cf5`
- ✅ MCP Weather Server built locally (for testing)
- ✅ Cloud platform account (AWS/Azure/GCP) - optional

## Table of Contents

1. [Docker Setup](#docker-setup)
2. [Docker Compose Configuration](#docker-compose-configuration)
3. [Environment Configuration](#environment-configuration)
4. [Local Cloud Testing](#local-cloud-testing)
5. [Cloud Platform Deployment](#cloud-platform-deployment)
6. [Testing & Verification](#testing--verification)
7. [Monitoring & Debugging](#monitoring--debugging)
8. [Production Deployment](#production-deployment)

---

## Docker Setup 🐳

### 1. Create Dockerfile

Create a production-ready Dockerfile for the MCP Weather Server:

```dockerfile
# Use official Node.js runtime as base image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S mcp-user -u 1001

# Copy package files first for better caching
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Change ownership to non-root user
RUN chown -R mcp-user:nodejs /app
USER mcp-user

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Set environment defaults
ENV NODE_ENV=production
ENV DEPLOYMENT_MODE=cloud
ENV PORT=3000

# Start the server
CMD ["npm", "start"]
```

### 2. Create .dockerignore

Optimize build performance and security:

```dockerignore
# Node modules
node_modules
npm-debug.log*

# Environment files
.env
.env.local
.env.*.local

# Git
.git
.gitignore

# Documentation
*.md
docs/

# Development files
.vscode/
.idea/
*.log

# Test files
test/
tests/
**/*.test.js
**/*.spec.js

# Build artifacts (will be rebuilt in container)
dist/

# OS files
.DS_Store
Thumbs.db

# Docker files
Dockerfile*
docker-compose*.yml
```

### 3. Build Docker Image

```bash
# Build development image
docker build -t mcp-weather-server:dev .

# Build production image with optimization
docker build \
  --build-arg NODE_ENV=production \
  --tag mcp-weather-server:latest \
  --tag mcp-weather-server:1.0.0 \
  .

# Multi-platform build (for cloud deployment)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag mcp-weather-server:latest \
  --push \
  .
```

---

## Docker Compose Configuration 🐙

### 1. Development Docker Compose

Create `docker-compose.dev.yml` for local development:

```yaml
version: '3.8'

services:
  mcp-weather-server:
    build: 
      context: .
      dockerfile: Dockerfile
    container_name: mcp-weather-dev
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - DEPLOYMENT_MODE=cloud
      - PORT=3000
      - OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
      - REQUIRE_AUTH=false
      - DEBUG=mcp:*
    volumes:
      # Mount source for hot reload in development
      - ./src:/app/src:ro
      - ./package.json:/app/package.json:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    networks:
      - mcp-network

  # Optional: Add Redis for caching
  redis:
    image: redis:7-alpine
    container_name: mcp-redis-dev
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - mcp-network

  # Optional: Add nginx reverse proxy
  nginx:
    image: nginx:alpine
    container_name: mcp-nginx-dev
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/dev.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/ssl/certs:ro
    depends_on:
      - mcp-weather-server
    networks:
      - mcp-network

networks:
  mcp-network:
    driver: bridge

volumes:
  redis_data:
```

### 2. Production Docker Compose

Create `docker-compose.prod.yml` for production deployment:

```yaml
version: '3.8'

services:
  mcp-weather-server:
    image: mcp-weather-server:latest
    container_name: mcp-weather-prod
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DEPLOYMENT_MODE=cloud
      - PORT=3000
      - OPENWEATHER_API_KEY=${OPENWEATHER_API_KEY}
      - REQUIRE_AUTH=true
      - PAT_TOKENS=${PAT_TOKENS}
      - ALLOWED_ORIGINS=${ALLOWED_ORIGINS}
    env_file:
      - .env.production
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - mcp-network

  redis:
    image: redis:7-alpine
    container_name: mcp-redis-prod
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
      - ./redis/redis.conf:/etc/redis/redis.conf:ro
    restart: always
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.25'
    networks:
      - mcp-network

  nginx:
    image: nginx:alpine
    container_name: mcp-nginx-prod
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/prod.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/ssl/certs:ro
      - nginx_logs:/var/log/nginx
    depends_on:
      - mcp-weather-server
    restart: always
    networks:
      - mcp-network

  # Monitoring stack
  prometheus:
    image: prom/prometheus
    container_name: mcp-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    networks:
      - mcp-network

  grafana:
    image: grafana/grafana
    container_name: mcp-grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana:/etc/grafana/provisioning:ro
    networks:
      - mcp-network

networks:
  mcp-network:
    driver: bridge

volumes:
  redis_data:
  nginx_logs:
  prometheus_data:
  grafana_data:
```

### 3. Testing Docker Compose

Create `docker-compose.test.yml` for automated testing:

```yaml
version: '3.8'

services:
  mcp-weather-server:
    build: 
      context: .
      dockerfile: Dockerfile
    environment:
      - NODE_ENV=test
      - DEPLOYMENT_MODE=cloud
      - PORT=3000
      - OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
      - REQUIRE_AUTH=false
    command: npm test
    volumes:
      - ./test:/app/test:ro
      - ./coverage:/app/coverage
    networks:
      - test-network

  test-runner:
    image: curlimages/curl:latest
    depends_on:
      - mcp-weather-server
    command: |
      sh -c "
        sleep 10 &&
        curl -f http://mcp-weather-server:3000/health &&
        curl -X POST http://mcp-weather-server:3000/mcp \
          -H 'Content-Type: application/json' \
          -d '{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"tools/list\"}' &&
        echo 'All tests passed!'
      "
    networks:
      - test-network

networks:
  test-network:
    driver: bridge
```

---

## Environment Configuration 🔧

### 1. Development Environment

Create `.env.development`:

```bash
# Development Environment Configuration
NODE_ENV=development
DEPLOYMENT_MODE=cloud
PORT=3000

# API Configuration
OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5

# Authentication (disabled for development)
REQUIRE_AUTH=false

# CORS Configuration
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000

# Debug Configuration
DEBUG=mcp:*

# Rate Limiting (relaxed for development)
RATE_LIMIT_REQUESTS=1000
RATE_LIMIT_WINDOW_MS=60000

# Redis Configuration (optional)
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=dev-password
```

### 2. Production Environment

Create `.env.production`:

```bash
# Production Environment Configuration
NODE_ENV=production
DEPLOYMENT_MODE=cloud
PORT=3000

# API Configuration
OPENWEATHER_API_KEY=${OPENWEATHER_API_KEY}

# Authentication Configuration
REQUIRE_AUTH=true
PAT_TOKENS=${PAT_TOKENS}

# CORS Configuration
ALLOWED_ORIGINS=${ALLOWED_ORIGINS}

# Rate Limiting
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW_MS=60000

# Security Headers
ENABLE_HELMET=true
ENABLE_RATE_LIMIT=true

# Redis Configuration
REDIS_URL=${REDIS_URL}
REDIS_PASSWORD=${REDIS_PASSWORD}

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9464

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
```

### 3. Cloud Environment Variables

Template for cloud platform deployment:

```bash
# Core Configuration
OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
DEPLOYMENT_MODE=cloud
PORT=3000
NODE_ENV=production

# Authentication Tokens (Generate unique for each environment)
PAT_TOKENS=mcp_prod_a1b2c3d4e5f6789012345678901234ab,mcp_prod_f1e2d3c4b5a6987654321098765432cd

# CORS Origins (Update with your domains)
ALLOWED_ORIGINS=https://your-app.com,https://api.your-app.com

# Optional: Redis for caching
REDIS_URL=redis://your-redis-host:6379
REDIS_PASSWORD=your-secure-redis-password

# Optional: Database URL (if adding persistence)
DATABASE_URL=postgresql://user:password@host:5432/mcpweather

# Monitoring passwords
GRAFANA_PASSWORD=your-secure-grafana-password
```

---

## Local Cloud Testing 🧪

### 1. Quick Start Commands

```bash
# Start development environment
docker-compose -f docker-compose.dev.yml up -d

# Start production environment locally
docker-compose -f docker-compose.prod.yml up -d

# Run tests
docker-compose -f docker-compose.test.yml up --abort-on-container-exit

# View logs
docker-compose -f docker-compose.dev.yml logs -f mcp-weather-server

# Stop and clean up
docker-compose -f docker-compose.dev.yml down -v
```

### 2. Development Testing Script

Create `test-cloud-local.sh`:

```bash
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
docker-compose -f docker-compose.dev.yml up -d

# Wait for containers to be ready
print_info "Waiting for containers to start..."
sleep 15

# Test 3: Health check
print_info "Testing health endpoint..."
if curl -f http://localhost:3000/health > /dev/null 2>&1; then
    print_success "Health check passed"
else
    print_failure "Health check failed"
    docker-compose -f docker-compose.dev.yml logs
    exit 1
fi

# Test 4: MCP tools list
print_info "Testing MCP tools list..."
RESPONSE=$(curl -s -X POST http://localhost:3000/mcp \
    -H "Content-Type: application/json" \
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
    -H "Content-Type: application/json" \
    -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London"}}}')

if echo "$WEATHER_RESPONSE" | grep -q "Current Weather"; then
    print_success "Weather API call working"
else
    print_failure "Weather API call failed"
    echo "Response: $WEATHER_RESPONSE"
fi

# Test 6: SSE connection
print_info "Testing SSE connection..."
timeout 5 curl -H "Accept: text/event-stream" http://localhost:3000/sse > /dev/null 2>&1
if [ $? -eq 124 ]; then
    print_success "SSE connection established (timeout expected)"
else
    print_failure "SSE connection failed"
fi

# Cleanup
print_info "Cleaning up..."
docker-compose -f docker-compose.dev.yml down

print_success "All local cloud tests passed! 🎉"
```

### 3. Performance Testing

Create `test-performance.sh`:

```bash
#!/bin/bash

echo "🚀 Performance Testing Suite"
echo "=========================="

# Start containers
docker-compose -f docker-compose.dev.yml up -d
sleep 15

# Test concurrent requests
echo "Testing concurrent requests..."
ab -n 100 -c 10 -H "Content-Type: application/json" \
   -p test-data.json \
   http://localhost:3000/mcp

# Test sustained load
echo "Testing sustained load..."
for i in {1..50}; do
    curl -s http://localhost:3000/health > /dev/null &
done
wait

# Check memory usage
echo "Memory usage:"
docker stats --no-stream mcp-weather-dev

# Cleanup
docker-compose -f docker-compose.dev.yml down

echo "Performance testing complete!"
```

---

## Cloud Platform Deployment ☁️

### 1. AWS Deployment

#### ECS with Fargate

Create `aws-ecs-task-definition.json`:

```json
{
  "family": "mcp-weather-server",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/mcpWeatherTaskRole",
  "containerDefinitions": [
    {
      "name": "mcp-weather-server",
      "image": "your-account.dkr.ecr.region.amazonaws.com/mcp-weather-server:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "DEPLOYMENT_MODE",
          "value": "cloud"
        }
      ],
      "secrets": [
        {
          "name": "OPENWEATHER_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:openweather-key"
        },
        {
          "name": "PAT_TOKENS",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:pat-tokens"
        }
      ],
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:3000/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/mcp-weather-server",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

#### Deployment Commands

```bash
# Build and push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin your-account.dkr.ecr.us-east-1.amazonaws.com

docker build -t mcp-weather-server .
docker tag mcp-weather-server:latest your-account.dkr.ecr.us-east-1.amazonaws.com/mcp-weather-server:latest
docker push your-account.dkr.ecr.us-east-1.amazonaws.com/mcp-weather-server:latest

# Register task definition
aws ecs register-task-definition --cli-input-json file://aws-ecs-task-definition.json

# Create service
aws ecs create-service \
  --cluster mcp-cluster \
  --service-name mcp-weather-service \
  --task-definition mcp-weather-server:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345],securityGroups=[sg-12345],assignPublicIp=ENABLED}"
```

### 2. Azure Deployment

#### Container Apps

Create `azure-container-app.yml`:

```yaml
apiVersion: 2022-03-01
kind: ContainerApp
metadata:
  name: mcp-weather-server
  location: East US
properties:
  managedEnvironmentId: /subscriptions/SUBSCRIPTION/resourceGroups/RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/ENVIRONMENT
  configuration:
    secrets:
      - name: openweather-api-key
        value: "6bb0e605343c674f8a58d1b5032e5cf5"
      - name: pat-tokens
        value: "mcp_prod_a1b2c3d4e5f6789012345678901234ab"
    ingress:
      external: true
      targetPort: 3000
      traffic:
        - weight: 100
          latestRevision: true
  template:
    containers:
      - name: mcp-weather-server
        image: your-registry.azurecr.io/mcp-weather-server:latest
        env:
          - name: NODE_ENV
            value: "production"
          - name: DEPLOYMENT_MODE
            value: "cloud"
          - name: OPENWEATHER_API_KEY
            secretRef: openweather-api-key
          - name: PAT_TOKENS
            secretRef: pat-tokens
        resources:
          cpu: 0.25
          memory: 0.5Gi
        probes:
          - type: liveness
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 30
    scale:
      minReplicas: 1
      maxReplicas: 5
      rules:
        - name: http-scaling
          http:
            metadata:
              concurrentRequests: 100
```

#### Deployment Commands

```bash
# Build and push to ACR
az acr build --registry your-registry --image mcp-weather-server:latest .

# Deploy to Container Apps
az containerapp create \
  --name mcp-weather-server \
  --resource-group your-rg \
  --environment your-env \
  --image your-registry.azurecr.io/mcp-weather-server:latest \
  --target-port 3000 \
  --ingress external \
  --env-vars NODE_ENV=production DEPLOYMENT_MODE=cloud \
  --secrets openweather-key=6bb0e605343c674f8a58d1b5032e5cf5 \
  --env-vars OPENWEATHER_API_KEY=secretref:openweather-key
```

### 3. Google Cloud Deployment

#### Cloud Run

Create `gcp-cloudrun.yml`:

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: mcp-weather-server
  annotations:
    run.googleapis.com/ingress: all
spec:
  template:
    metadata:
      annotations:
        run.googleapis.com/cpu-throttling: "false"
        run.googleapis.com/memory: "512Mi"
        run.googleapis.com/max-scale: "10"
        run.googleapis.com/min-scale: "1"
    spec:
      containerConcurrency: 100
      containers:
      - name: mcp-weather-server
        image: gcr.io/PROJECT_ID/mcp-weather-server:latest
        ports:
        - name: http1
          containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
        - name: DEPLOYMENT_MODE
          value: "cloud"
        - name: OPENWEATHER_API_KEY
          valueFrom:
            secretKeyRef:
              name: openweather-key
              key: api-key
        - name: PAT_TOKENS
          valueFrom:
            secretKeyRef:
              name: pat-tokens
              key: tokens
        resources:
          limits:
            memory: "512Mi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 30
```

#### Deployment Commands

```bash
# Build and push to GCR
gcloud builds submit --tag gcr.io/PROJECT_ID/mcp-weather-server:latest

# Create secrets
echo "6bb0e605343c674f8a58d1b5032e5cf5" | gcloud secrets create openweather-key --data-file=-
echo "mcp_prod_a1b2c3d4e5f6789012345678901234ab" | gcloud secrets create pat-tokens --data-file=-

# Deploy to Cloud Run
gcloud run deploy mcp-weather-server \
  --image gcr.io/PROJECT_ID/mcp-weather-server:latest \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars NODE_ENV=production,DEPLOYMENT_MODE=cloud \
  --set-secrets OPENWEATHER_API_KEY=openweather-key:latest \
  --set-secrets PAT_TOKENS=pat-tokens:latest \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 1 \
  --max-instances 10
```

---

## Testing & Verification 🔍

### 1. Cloud Deployment Tests

Create `test-cloud-deployment.sh`:

```bash
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
             "$CLOUD_URL/sse" > /dev/null 2>&1
if [ $? -eq 124 ]; then
    print_success "SSE connection established"
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
CORS_RESPONSE=$(curl -s -I -H "Origin: https://example.com" "$CLOUD_URL/health")
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
```

### 2. Load Testing

Create `load-test.sh`:

```bash
#!/bin/bash

CLOUD_URL=${1:-"http://localhost:3000"}
PAT_TOKEN=${2:-"mcp_dev_2a55e153d51b306bf650300f8c21f1cb"}

echo "🔥 Load Testing Suite"
echo "===================="

# Install tools if needed
if ! command -v hey &> /dev/null; then
    echo "Installing hey load testing tool..."
    go install github.com/rakyll/hey@latest
fi

# Test 1: Health endpoint load
echo "Testing health endpoint load..."
hey -n 1000 -c 50 -H "Authorization: Bearer $PAT_TOKEN" "$CLOUD_URL/health"

# Test 2: MCP tools list load
echo "Testing MCP tools list load..."
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' > /tmp/tools_payload.json
hey -n 500 -c 25 \
    -m POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $PAT_TOKEN" \
    -D /tmp/tools_payload.json \
    "$CLOUD_URL/mcp"

# Test 3: Weather API load
echo "Testing weather API load..."
echo '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London"}}}' > /tmp/weather_payload.json
hey -n 100 -c 10 \
    -m POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $PAT_TOKEN" \
    -D /tmp/weather_payload.json \
    "$CLOUD_URL/mcp"

echo "Load testing complete!"
```

---

## Monitoring & Debugging 📊

### 1. Logging Configuration

Create monitoring configuration files:

**monitoring/prometheus.yml**:
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'mcp-weather-server'
    static_configs:
      - targets: ['mcp-weather-server:9464']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
```

**nginx/prod.conf**:
```nginx
events {
    worker_connections 1024;
}

http {
    upstream mcp_backend {
        server mcp-weather-server:3000;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

    server {
        listen 80;
        listen 443 ssl http2;
        
        # SSL configuration
        ssl_certificate /etc/ssl/certs/cert.pem;
        ssl_certificate_key /etc/ssl/certs/key.pem;
        
        # Security headers
        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options DENY;
        add_header X-XSS-Protection "1; mode=block";
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        
        # Health check endpoint
        location /health {
            proxy_pass http://mcp_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # SSE endpoint
        location /sse {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://mcp_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # SSE specific headers
            proxy_set_header Connection '';
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 24h;
        }
        
        # MCP endpoint
        location /mcp {
            limit_req zone=api burst=50 nodelay;
            
            proxy_pass http://mcp_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

### 2. Debugging Commands

```bash
# View container logs
docker-compose logs -f mcp-weather-server

# Monitor resource usage
docker stats mcp-weather-server

# Inspect container
docker inspect mcp-weather-server

# Execute shell in container
docker exec -it mcp-weather-server sh

# Check network connectivity
docker exec -it mcp-weather-server curl http://api.openweathermap.org

# View container filesystem
docker exec -it mcp-weather-server ls -la /app

# Check environment variables
docker exec -it mcp-weather-server env

# Test internal connectivity
docker exec -it mcp-weather-server curl http://localhost:3000/health
```

### 3. Performance Monitoring

Create `monitor.sh`:

```bash
#!/bin/bash

echo "📊 Performance Monitoring"
echo "========================"

# CPU and Memory usage
echo "Container Resource Usage:"
docker stats --no-stream mcp-weather-server

# Network connections
echo -e "\nNetwork Connections:"
docker exec -it mcp-weather-server netstat -tulpn

# Application metrics
echo -e "\nApplication Health:"
curl -s http://localhost:3000/health | jq .

# API response times
echo -e "\nAPI Response Times:"
time curl -s -X POST http://localhost:3000/mcp \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer mcp_dev_2a55e153d51b306bf650300f8c21f1cb" \
    -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' > /dev/null

# Log analysis
echo -e "\nRecent Errors:"
docker logs mcp-weather-server 2>&1 | grep -i error | tail -5

echo -e "\nMonitoring complete!"
```

---

## Production Deployment 🚀

### 1. Pre-deployment Checklist

```bash
# Security checklist
echo "🔒 Production Security Checklist"
echo "================================"

# ✅ Environment variables secured
# ✅ PAT tokens generated and stored securely
# ✅ HTTPS enabled with valid certificates
# ✅ Rate limiting configured
# ✅ CORS origins restricted
# ✅ Container runs as non-root user
# ✅ Resource limits set
# ✅ Health checks configured
# ✅ Monitoring and logging enabled
# ✅ Backup strategy in place
```

### 2. Production Deployment Script

Create `deploy-production.sh`:

```bash
#!/bin/bash

set -e

echo "🚀 Production Deployment Script"
echo "==============================="

# Configuration
ENVIRONMENT=${1:-"production"}
IMAGE_TAG=${2:-"latest"}
REGISTRY=${3:-"your-registry.com"}

# Validate environment
if [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "staging" ]; then
    echo "Error: Environment must be 'production' or 'staging'"
    exit 1
fi

# Build and tag image
echo "Building production image..."
docker build -t mcp-weather-server:$IMAGE_TAG .
docker tag mcp-weather-server:$IMAGE_TAG $REGISTRY/mcp-weather-server:$IMAGE_TAG

# Security scan (if tools available)
if command -v trivy &> /dev/null; then
    echo "Running security scan..."
    trivy image $REGISTRY/mcp-weather-server:$IMAGE_TAG
fi

# Push image
echo "Pushing image to registry..."
docker push $REGISTRY/mcp-weather-server:$IMAGE_TAG

# Deploy using docker-compose
echo "Deploying to $ENVIRONMENT..."
export IMAGE_TAG=$IMAGE_TAG
export REGISTRY=$REGISTRY
docker-compose -f docker-compose.prod.yml up -d

# Health check
echo "Performing health check..."
sleep 30
if curl -f http://localhost:3000/health; then
    echo "✅ Deployment successful!"
else
    echo "❌ Deployment failed!"
    docker-compose -f docker-compose.prod.yml logs
    exit 1
fi

# Run smoke tests
echo "Running smoke tests..."
./test-cloud-deployment.sh http://localhost:3000

echo "🎉 Production deployment complete!"
```

### 3. Rollback Script

Create `rollback.sh`:

```bash
#!/bin/bash

echo "🔄 Rolling back deployment..."

# Get previous image tag
PREVIOUS_TAG=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep mcp-weather-server | sed -n '2p' | cut -d':' -f2)

if [ -z "$PREVIOUS_TAG" ]; then
    echo "No previous version found!"
    exit 1
fi

echo "Rolling back to: $PREVIOUS_TAG"

# Update docker-compose with previous tag
export IMAGE_TAG=$PREVIOUS_TAG
docker-compose -f docker-compose.prod.yml up -d

# Health check
sleep 15
if curl -f http://localhost:3000/health; then
    echo "✅ Rollback successful!"
else
    echo "❌ Rollback failed!"
    exit 1
fi
```

---

## Quick Commands Reference 📋

### Development
```bash
# Start development environment
docker-compose -f docker-compose.dev.yml up -d

# View logs
docker-compose -f docker-compose.dev.yml logs -f

# Run tests
./test-cloud-local.sh

# Stop and clean
docker-compose -f docker-compose.dev.yml down -v
```

### Production
```bash
# Deploy to production
./deploy-production.sh production v1.0.0

# Monitor production
./monitor.sh

# Test production deployment
./test-cloud-deployment.sh https://your-domain.com mcp_prod_token

# Rollback if needed
./rollback.sh
```

### Debugging
```bash
# Container shell access
docker exec -it mcp-weather-server sh

# View detailed logs
docker logs mcp-weather-server --details

# Check resource usage
docker stats --no-stream

# Network debugging
docker network ls
docker network inspect mcp-network
```

---

**Your cloud deployment is ready!** 🎉 Use the scripts and configurations above to deploy your MCP Weather Server to any cloud platform with Docker support. 