FROM node:22-alpine
WORKDIR /app
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --chown=node:node server.mjs db.mjs accounts.mjs challenge_api.mjs oauth.mjs social_friends.mjs profile_nutrition.mjs ./
USER node
ENV HOST=0.0.0.0 PORT=8000
EXPOSE 8000
CMD ["node", "server.mjs"]
