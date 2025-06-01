# Docker & Cloud Commands Quick Reference 🐳

## Prerequisites Check ✅

```bash
# Quick cloud setup validation
./quick-cloud-test.sh
```

## Development Commands 🛠️

### Start Development Environment
```bash
# Start all services (mcp-weather-server, redis, nginx)
docker-compose -f docker-compose.dev.yml up -d

# Start only the MCP server
docker-compose -f docker-compose.dev.yml up -d mcp-weather-server

# View logs
docker-compose -f docker-compose.dev.yml logs -f
docker-compose -f docker-compose.dev.yml logs -f mcp-weather-server

# Stop and remove containers
docker-compose -f docker-compose.dev.yml down

# Stop and remove everything including volumes
docker-compose -f docker-compose.dev.yml down -v
```

### Development Testing
```bash
# Run full local cloud test suite
./test-cloud-local.sh

# Manual health check
curl http://localhost:3000/health

# Test MCP tools
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'

# Test weather API
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "get_current_weather", "arguments": {"location": "London"}}}'
```

## Production Commands 🚀

### Build and Deploy
```bash
# Build production image
docker build -t mcp-weather-server:latest .

# Start production environment
docker-compose -f docker-compose.prod.yml up -d

# Deploy with full pipeline
./deploy-production.sh production v1.0.0

# Test production deployment
./test-cloud-deployment.sh http://localhost:3000 your-pat-token
```

### Production Management
```bash
# View production logs
docker-compose -f docker-compose.prod.yml logs -f

# Monitor resource usage
docker stats mcp-weather-prod

# Scale the service
docker-compose -f docker-compose.prod.yml up -d --scale mcp-weather-server=3

# Rolling update
docker-compose -f docker-compose.prod.yml pull
docker-compose -f docker-compose.prod.yml up -d

# Backup volumes
docker run --rm -v mcp_redis_data:/data -v $(pwd):/backup alpine tar czf /backup/redis-backup.tar.gz -C /data .
```

## Debugging Commands 🔍

### Container Inspection
```bash
# Execute shell in container
docker exec -it mcp-weather-dev sh

# View container details
docker inspect mcp-weather-dev

# Check processes in container
docker exec -it mcp-weather-dev ps aux

# View environment variables
docker exec -it mcp-weather-dev env

# Check network connectivity
docker exec -it mcp-weather-dev curl http://api.openweathermap.org
```

### Logs and Monitoring
```bash
# Follow real-time logs
docker logs -f mcp-weather-dev

# View last 100 lines
docker logs --tail 100 mcp-weather-dev

# View logs with timestamps
docker logs -t mcp-weather-dev

# Search logs for errors
docker logs mcp-weather-dev 2>&1 | grep -i error
```

### Network Debugging
```bash
# List networks
docker network ls

# Inspect network
docker network inspect mcp-network

# Test connectivity between containers
docker exec -it mcp-weather-dev ping redis

# View port mappings
docker port mcp-weather-dev
```

## Cloud Platform Deployment ☁️

### AWS (ECS/Fargate)
```bash
# Build and push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com
docker tag mcp-weather-server:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/mcp-weather-server:latest
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/mcp-weather-server:latest

# Deploy to ECS
aws ecs update-service --cluster mcp-cluster --service mcp-weather-service --force-new-deployment
```

### Azure (Container Apps)
```bash
# Build and push to ACR
az acr build --registry myregistry --image mcp-weather-server:latest .

# Deploy to Container Apps
az containerapp update --name mcp-weather --resource-group myRG --image myregistry.azurecr.io/mcp-weather-server:latest
```

### Google Cloud (Cloud Run)
```bash
# Build and push to GCR
gcloud builds submit --tag gcr.io/PROJECT_ID/mcp-weather-server:latest

# Deploy to Cloud Run
gcloud run deploy mcp-weather --image gcr.io/PROJECT_ID/mcp-weather-server:latest --platform managed --region us-central1
```

## Environment Management 🔧

### Development Environment
```bash
# Copy environment template
cp env.example .env.development

# Edit development settings
export OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
export DEPLOYMENT_MODE=cloud
export REQUIRE_AUTH=false
```

### Production Environment
```bash
# Copy production template
cp env.production.example .env.production

# Generate PAT tokens
node -e "const crypto = require('crypto'); console.log('mcp_prod_' + crypto.randomBytes(16).toString('hex'));"

# Set production variables
export OPENWEATHER_API_KEY=6bb0e605343c674f8a58d1b5032e5cf5
export PAT_TOKENS=mcp_prod_your_generated_token
export ALLOWED_ORIGINS=https://your-domain.com
export REQUIRE_AUTH=true
```

## Monitoring and Health Checks 📊

### Health Monitoring
```bash
# Health check endpoint
curl http://localhost:3000/health

# Detailed health with auth
curl -H "Authorization: Bearer your-pat-token" http://localhost:3000/health

# Monitor all containers
docker-compose -f docker-compose.prod.yml ps
```

### Performance Monitoring
```bash
# Resource usage
docker stats --no-stream

# Container resource limits
docker inspect mcp-weather-prod | grep -A 10 Resources

# Network usage
docker exec -it mcp-weather-prod netstat -tuln
```

### Application Metrics
```bash
# Prometheus metrics (if enabled)
curl http://localhost:9090/metrics

# Grafana dashboard
open http://localhost:3001
```

## Troubleshooting 🔧

### Common Issues
```bash
# Port already in use
sudo lsof -i :3000
docker-compose down

# Container won't start
docker-compose logs mcp-weather-server
docker inspect mcp-weather-server

# Network connectivity issues
docker network prune
docker-compose down && docker-compose up -d

# Volume permission issues
docker exec -it mcp-weather-server ls -la /app
docker exec -it mcp-weather-server whoami
```

### Clean Up Commands
```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes
docker volume prune

# Remove unused networks
docker network prune

# Clean everything (CAUTION)
docker system prune -a --volumes
```

## Load Testing 🔥

### Basic Load Testing
```bash
# Install hey if not available
go install github.com/rakyll/hey@latest

# Test health endpoint
hey -n 1000 -c 50 http://localhost:3000/health

# Test MCP endpoint with auth
hey -n 500 -c 25 -H "Authorization: Bearer your-pat-token" -m POST -H "Content-Type: application/json" -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' http://localhost:3000/mcp
```

### Stress Testing
```bash
# Concurrent health checks
for i in {1..100}; do curl -s http://localhost:3000/health > /dev/null & done; wait

# Monitor during load
watch docker stats mcp-weather-dev
```

## Quick Deployment Pipeline 🚀

```bash
# 1. Test locally
./quick-cloud-test.sh

# 2. Run full test suite
./test-cloud-local.sh

# 3. Build and test production image
docker build -t mcp-weather-server:latest .
docker run -d -p 3000:3000 --name test-prod mcp-weather-server:latest
sleep 10
curl http://localhost:3000/health
docker stop test-prod && docker rm test-prod

# 4. Deploy to production
./deploy-production.sh production v1.0.0

# 5. Verify deployment
./test-cloud-deployment.sh http://localhost:3000 your-pat-token
```

---

**Ready for cloud deployment!** 🎉 Use these commands to develop, test, and deploy your MCP Weather Server in any cloud environment. 