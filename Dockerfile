FROM node:20-alpine

WORKDIR /

# Copy main package files and install dependencies
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Copy all source files
COPY . .

# Install Convex CLI globally
RUN npm install -g convex

# Build Convex functions once
RUN convex dev --once

# Expose port for Dokku
EXPOSE 3000

# Start Convex in production mode
CMD ["convex", "dev", "--prod", "--listen", "0.0.0.0:3000"]

