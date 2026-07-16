# Node 18 est en fin de vie depuis avril 2025 (et portait 17 CVE OS HIGH/CRITICAL).
# Node 22 est la LTS courante : 0 CVE OS.
FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
# --only=production est déprécié depuis npm 9 (livré avec Node 22), remplacé par --omit=dev
RUN npm ci --omit=dev

COPY . .

EXPOSE 3000

USER node

CMD ["node", "app.js"]
