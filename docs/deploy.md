# Self-hosting the backend

The backend is one container, `ghcr.io/mikaellecam/motu-backend`: the Go server, the lessons, and a volume
for its SQLite file and the lessons' frozen datasets. It needs Docker and a Twelve Data API key (free Basic
plan, ADR-004). No checkout of the repository is needed.

## 1. Configure

Write an `.env` from [`backend/.env.example`](../backend/.env.example) and set `TWELVEDATA_API_KEY`. Leave
`DB_PATH` and `CONTENT_DIR` unset: the image keeps both in its volume.

## 2. Run

```bash
docker run -d --name motu --restart unless-stopped \
  --env-file .env \
  -v motu-data:/app/data \
  -p 127.0.0.1:8080:8080 \
  ghcr.io/mikaellecam/motu-backend:1
```

`:1` follows the 1.x releases; `:latest` is the newest, and `:1.2.3` stays put. Images exist for amd64 and
arm64.

Each start, the image puts its lessons in the volume, next to the datasets an earlier start froze. It freezes
the missing datasets from their recipes, removes those no recipe lists any more (ADR-007), then starts the
server. The first start freezes them all: about 15 provider credits and a few minutes before the server
listens. If freezing fails, the server starts anyway, and the lessons wait for the next start.

The server publishes, for each island, the content pack versions without drafts (`contentcheck -release`,
ADR-006). A version with a problem is left out and logged (`content pack not published`); market data is
served either way.

The first start also backfills every asset from `DATA_FLOOR`: about 60 provider credits at 8 per minute, so
expect several minutes more. The API answers meanwhile, with partial history. After that, a sync runs on
weekdays at 17:00 New York time.

## 3. Check

```bash
docker inspect -f '{{.State.Health.Status}}' motu   # healthy: /healthz answers
docker logs -f motu                                 # freeze, then the server's JSON logs
curl -s localhost:8080/v1/assets
curl -s localhost:8080/v1/content/manifest          # the published content packs
```

The backfill is done when the logs say `market data up to date`.

## 4. Expose over HTTPS

Put a reverse proxy in front of `127.0.0.1:8080`. With Caddy, which provisions the certificate itself:

```
api.example.org {
	reverse_proxy 127.0.0.1:8080
}
```

Behind a proxy every request comes from the proxy's address, so the server's per-IP limit would throttle all
clients as one. Set `API_REQUESTS_PER_MINUTE=0` and rate-limit at the proxy instead.

## Update

```bash
docker pull ghcr.io/mikaellecam/motu-backend:1
docker rm -f motu   # then the docker run command above
```

The volume keeps the data, and the server migrates its schema at start. New lessons come with new images:
the start puts them in place and freezes only the datasets they add.

## Backup

Everything in the volume can be rebuilt (the database by a backfill, the datasets by freezing them), so a
backup only saves time and credits. To take one, stop the container so SQLite is not mid-write, copy the file
out, and start it again:

```bash
docker stop motu
docker run --rm -v motu-data:/data -v "$PWD":/backup alpine cp /data/market.db /backup/
docker start motu
```

## Building the image yourself

From the repository root, `docker build -f backend/Dockerfile -t motu-backend .`, then run `motu-backend` in
place of `ghcr.io/mikaellecam/motu-backend:1`. A `v*` tag publishes the image (`.github/workflows/image.yml`).
