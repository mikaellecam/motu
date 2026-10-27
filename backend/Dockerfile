# Build from the repository root: docker build -f backend/Dockerfile -t motu-backend .
# Self-hosting steps: docs/deploy.md. The image carries the lessons (content/) but never a dataset (ADR-007,
# Dockerfile.dockerignore): it freezes them at start, into its data volume (start.sh).
FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ .
# Pure-Go SQLite, so no cgo, and the compiler runs natively for every target. The tz database is compiled in
# (timetzdata): market hours need America/New_York whatever the image ships.
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -tags timetzdata \
      -o /server ./cmd/server && \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -tags timetzdata \
      -o /freeze ./cmd/freeze

FROM alpine:3.24
RUN adduser -D -H app && mkdir -p /app/data && chown app /app/data
WORKDIR /app
COPY --from=build /server /freeze /usr/local/bin/
COPY backend/start.sh /usr/local/bin/motu-start
COPY content /app/content
USER app
# DB_PATH defaults to data/market.db; the content and its frozen datasets live beside it (start.sh).
VOLUME /app/data
ENV CONTENT_DIR=/app/data/content
EXPOSE 8080
# The first start freezes the datasets (about 15 provider credits, a few minutes) before the server listens.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5m \
  CMD wget -qO /dev/null "http://localhost:${PORT:-8080}/healthz" || exit 1
CMD ["motu-start"]
