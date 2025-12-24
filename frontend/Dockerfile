# Build stage
FROM node:18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production=false
COPY . .
RUN npm run build

# Production stage
FROM nginxinc/nginx-unprivileged:alpine

# Copy built assets
COPY --from=build /app/build /usr/share/nginx/html

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Use non-root user (nginx-unprivileged uses UID 101 by default, but OpenShift uses arbitrary UIDs)
USER 1001

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]