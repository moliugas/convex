FROM node:20-alpine

WORKDIR /

# Copy package files and install production dependencies
COPY package.json package-lock.json ./
RUN npm install --omit=dev

# Copy application source
COPY . .

# Environment
ENV NODE_ENV=production
# Default; Dokku sets $PORT at runtime
ENV PORT=3210

# Expose default port (informational)
EXPOSE 3210
EXPOSE 3211

# Start the server using the project script
CMD ["npm", "run", "start"]
