FROM node:14
WORKDIR /app
COPY package*.json ./
RUN npm install --legacy-peer-deps
COPY . .
ENV SEGREDO_SUPERSECRETO=valor-muito-secreto
EXPOSE 3000
CMD ["node", "src/index.js"]
