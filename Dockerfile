FROM node:20-alpine

ARG CACHEBUST=1

WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm install --omit=dev

# Copy all source files
COPY . .

# Install Convex CLI globally (optional — better to have in package.json)
RUN npm install -g convex

# Expose port for Dokku
ENV PORT=3210

EXPOSE ${PORT}
EXPOSE 3211