FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY . .
ENV PORT=8085
ENV NODE_ENV=production
EXPOSE 8085
CMD ["node", "server.js"]
