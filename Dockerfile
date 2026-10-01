# syntax=docker/dockerfile:1

FROM node:20-bookworm-slim AS web-builder
WORKDIR /src/web
RUN corepack enable
COPY web/package.json web/pnpm-lock.yaml web/pnpm-workspace.yaml web/.npmrc ./
RUN pnpm install --frozen-lockfile
COPY web/ ./
RUN pnpm build

FROM golang:1.25-bookworm AS api-builder
WORKDIR /src
COPY server/go.mod server/go.sum ./server/
WORKDIR /src/server
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -trimpath -ldflags='-s -w' -o /out/prism ./cmd/prism

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install --no-install-recommends --yes ca-certificates wget \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 prism \
    && useradd --system --uid 10001 --gid 10001 --home-dir /app --no-create-home prism \
    && mkdir -p /app/data /app/web/dist /app/server/configs \
    && chown -R prism:prism /app
WORKDIR /app
COPY --from=api-builder /out/prism /app/prism
COPY --from=api-builder /src/server/configs /app/server/configs
COPY --from=web-builder /src/web/dist /app/web/dist
USER prism
ENV HOST=0.0.0.0 \
    PORT=8080 \
    STORAGE_DB_DIR=/app/data
EXPOSE 8080
VOLUME ["/app/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["sh", "-c", "wget -q -O - http://127.0.0.1:${PORT:-8080}/health >/dev/null"]
ENTRYPOINT ["/app/prism"]
