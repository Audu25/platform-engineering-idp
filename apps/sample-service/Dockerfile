# Alpine rather than Debian slim, for what the scanner can act on. Debian 12
# carries around sixty high or critical findings that Debian marks "won't fix"
# or has not fixed, so a strict gate against it can never pass. Alpine's are all
# fixable, and the two lines below fix them: the OS packages are upgraded, and
# npm is removed because a service with no dependencies does not need a package
# manager in production — which also removes every finding in npm's own tree.
FROM node:24-alpine
ENV NODE_ENV=production PORT=8080
RUN apk upgrade --no-cache \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
WORKDIR /app
# No dependencies or build output: a builder stage would add no value here.
COPY --chown=node:node package.json ./
COPY --chown=node:node src/ ./src/
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.js"]
