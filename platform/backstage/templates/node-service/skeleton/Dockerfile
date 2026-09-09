FROM node:24-bookworm-slim
ENV NODE_ENV=production PORT=8080
WORKDIR /app
# No dependencies or build output: a builder stage would add no value here.
COPY --chown=node:node package.json ./
COPY --chown=node:node src/ ./src/
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.js"]
