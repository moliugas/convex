FROM node:20-alpine
ARG CACHEBUST=1
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install --omit=dev
COPY . .
RUN npm install -g convex
EXPOSE 3000
# Start the server using the project script
CMD ["sh", "-c", "convex dev --once && convex dev --prod --listen 0.0.0.0:3000"]
