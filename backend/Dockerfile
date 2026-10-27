# Build from this directory: docker build -t motu-backend .
# Self-hosting steps: docs/deploy.md.
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Pure-Go SQLite, so no cgo. The tz database is compiled in (timetzdata):
# market hours need America/New_York whatever the image ships.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -tags timetzdata -o /server ./cmd/server
# freeze rebuilds the content's datasets from their recipes (ADR-007, docs/deploy.md).
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -tags timetzdata -o /freeze ./cmd/freeze

FROM alpine:3.24
RUN adduser -D -H app && mkdir -p /app/data && chown app /app/data
WORKDIR /app
COPY --from=build /server /freeze /usr/local/bin/
USER app
# DB_PATH defaults to data/market.db, which is this volume.
VOLUME /app/data
# The content tree, mounted read-only (docs/deploy.md).
ENV CONTENT_DIR=/app/content
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -qO /dev/null "http://localhost:${PORT:-8080}/healthz" || exit 1
CMD ["server"]
