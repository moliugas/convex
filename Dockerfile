FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY . .

# Ensure Convex CLI is installed
RUN npm install -g convex

# Build Convex functions
RUN convex dev --once

EXPOSE 3000
CMD ["convex", "dev", "--prod", "--listen", "0.0.0.0:3000"]
