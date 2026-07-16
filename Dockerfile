FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production \
    PORT=5000

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src

EXPOSE 5000

USER node

CMD ["node", "src/server.js"]