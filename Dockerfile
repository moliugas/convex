FROM node:20-alpine

WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm install --omit=dev

# Copy all source files
COPY . .

# Install Convex CLI globally (optional — better to have in package.json)
RUN npm install -g convex

# Expose port for Dokku
EXPOSE 3000

# Start Convex in production mode
CMD ["convex", "dev", "--prod", "--listen", "0.0.0.0:3000"]
