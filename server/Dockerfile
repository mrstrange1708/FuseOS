# The control plane as one small image. Built from the repo root (the lockfile and the
# workspace manifest live there): docker build -f server/Dockerfile .
FROM node:22-alpine AS build
WORKDIR /repo
RUN corepack enable
# Every workspace's manifest, so the frozen lockfile matches; only the server installs.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY server/package.json server/
COPY website/package.json website/
COPY packages/proto/package.json packages/proto/
RUN pnpm install --frozen-lockfile --filter server
COPY server server
RUN pnpm --filter server build && pnpm --filter server deploy --prod /out

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /out ./
USER node
EXPOSE 3000
CMD ["node", "dist/index.js"]
