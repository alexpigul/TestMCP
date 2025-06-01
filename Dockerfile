# Use official Node.js runtime as base image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S mcp-user -u 1001

# Install curl for healthcheck
RUN apk add --no-cache curl

# Copy package files first for better caching
COPY package*.json ./

# Install all dependencies (including dev dependencies) for build
RUN npm ci

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Remove dev dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Change ownership to non-root user
RUN chown -R mcp-user:nodejs /app
USER mcp-user

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Set environment defaults
ENV NODE_ENV=production \
    DEPLOYMENT_MODE=cloud \
    PORT=3000

# Start the server
CMD ["npm", "start"] 