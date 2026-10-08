# Self-hosting the backend

The backend is one container: the Go server and its SQLite file on a volume. It needs Docker and a
Twelve Data API key (free Basic plan, ADR-004). Commands run from the repository root.

## 1. Configure

```bash
cp backend/.env.example backend/.env   # then set TWELVEDATA_API_KEY
```

Leave `DB_PATH` at its default: `data/market.db` is the image's volume. `.env` stays out of git and out of
the image (`backend/.dockerignore`).

## 2. Build and run

```bash
docker build -t finance-companion-backend backend
docker run -d --name finance-companion --restart unless-stopped \
  --env-file backend/.env \
  -v finance-companion-data:/app/data \
  -p 127.0.0.1:8080:8080 \
  finance-companion-backend
```

The first start backfills every asset from `DATA_FLOOR`: about 60 provider credits at 8 per minute, so
expect several minutes. The API answers meanwhile, with partial history. After that, a sync runs on weekdays
at 17:00 New York time.

## 3. Check

```bash
docker inspect -f '{{.State.Health.Status}}' finance-companion   # healthy: /healthz answers
docker logs -f finance-companion                                 # JSON logs
curl -s localhost:8080/v1/assets
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
git pull
docker build -t finance-companion-backend backend
docker rm -f finance-companion   # then the docker run command above
```

The volume keeps the data, and the server migrates its schema at start.

## Backup

Everything in the database can be rebuilt by a backfill, so a backup only saves time and credits. To take
one, stop the container so SQLite is not mid-write, copy the file out, and start it again:

```bash
docker stop finance-companion
docker run --rm -v finance-companion-data:/data -v "$PWD":/backup alpine cp /data/market.db /backup/
docker start finance-companion
```
