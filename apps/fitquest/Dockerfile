FROM node:22-alpine
WORKDIR /app
COPY --chown=node:node server.mjs accounts.mjs ./
RUN mkdir /data && chown node:node /data
USER node
ENV HOST=0.0.0.0 PORT=8000 FITQUEST_DB=/data/fitquest.sqlite
EXPOSE 8000
CMD ["node", "server.mjs"]
