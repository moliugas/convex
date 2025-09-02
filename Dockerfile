FROM ghcr.io/get-convex/convex-backend:08139ef318b1898dad7731910f49ba631631c902

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

# Start the server using the project script
CMD ["npm", "run", "start"]
