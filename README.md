# postgres

Docker images for **PostgreSQL 18** with optional **Chinese full-text search** ([`zhparser`](https://github.com/amutu/zhparser)) and **geospatial** ([PostGIS](https://postgis.net)) extensions. All images set the system locale to `zh_CN.UTF-8` and the timezone to `Asia/Shanghai`.

Images are published to GitHub Container Registry, and optionally to Docker Hub when `DOCKER_USERNAME` / `DOCKER_PASSWORD` repository secrets are configured:

| Tag | Base image | Extensions | Description |
| --- | --- | --- | --- |
| `ghcr.io/vnobo/postgres:18` | `postgres:18` | — | PostgreSQL 18 with `zh_CN.UTF-8` locale and `Asia/Shanghai` timezone. |
| `ghcr.io/vnobo/postgres:18-zhparser` | `postgres:18` | zhparser + scws | Adds Chinese full-text search. |
| `ghcr.io/vnobo/postgres:18-postgis` | `postgis/postgis:18-3.6` | PostGIS + zhparser + scws | Geospatial + Chinese full-text search. |
| `ghcr.io/vnobo/postgres:latest-postgis` | `postgis/postgis:18-3.6` | PostGIS + zhparser + scws | Rolling `latest` alias of the most recent `18-postgis` build (pushed on every `main`/tag build). |

## Tech stack & pinned versions

| Component | Version | Source | Notes |
| --- | --- | --- | --- |
| PostgreSQL | 18 | `postgres:18` | Floating to latest 18.x patch (security). |
| PostGIS | 3.6 (3.6.0) | `postgis/postgis:18-3.6` | Requires PostgreSQL 12–18. |
| scws (SCWS) | 1.2.3 | [hightman/scws](https://github.com/hightman/scws) | Chinese word-segmentation C library; pinned to release tag. |
| zhparser | commit `2e995c4` | [amutu/zhparser](https://github.com/amutu/zhparser) | Pinned to an explicit commit SHA for reproducible, supply-chain-safe builds. |

> **Upgrading zhparser:** bump `ARG ZHPARSER_COMMIT` in [`zhparser/Dockerfile`](./zhparser/Dockerfile) and [`postgis/Dockerfile`](./postgis/Dockerfile).

## Quick start

### Pull a prebuilt image

```bash
docker pull ghcr.io/vnobo/postgres:18
docker pull ghcr.io/vnobo/postgres:18-zhparser
docker pull ghcr.io/vnobo/postgres:18-postgis
```

### Run with Chinese search enabled

```bash
docker run --name pg -e POSTGRES_PASSWORD=secret -p 5432:5432 -d ghcr.io/vnobo/postgres:18-zhparser
```

Enable the extension and create a Chinese text search configuration:

```sql
CREATE EXTENSION IF NOT EXISTS zhparser;
CREATE TEXT SEARCH CONFIGURATION chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION chinese
  ADD MAPPING FOR n,v,a,i,e,l,x WITH simple;
```

```sql
SELECT to_tsvector('chinese', '支付宝使用很方便');
-- '支付宝':1 '方便':4 '使用':2
```

## Build from source

Each image is an independent Docker build context.

```bash
# Base locale image
docker build -t postgres:18 .

# zhparser image
docker build -t postgres:18-zhparser ./zhparser

# postgis image
docker build -t postgres:18-postgis ./postgis
```

Retarget the PostgreSQL major version:

```bash
docker build --build-arg PG_CONTAINER_VERSION=18 -t postgres:18 ./zhparser
```

## Verify the zhparser extension

[`zhparser/zhparser.sql`](./zhparser/zhparser.sql) is an idempotent verification script. Run it against a running `18-zhparser` or `18-postgis` container:

```bash
docker run --rm -e POSTGRES_PASSWORD=test -p 5432:5432 postgres:18-zhparser &
psql -h localhost -U postgres -f zhparser/zhparser.sql
```

It asserts the extension installs, custom words sync, and Chinese text search (`ts_debug`/`to_tsvector`/`to_tsquery`) behaves correctly.

## Directory structure

```
.
├── Dockerfile              # Base image: postgres:18 + zh_CN.UTF-8 locale + Asia/Shanghai TZ
├── zhparser/
│   ├── Dockerfile          # Multi-stage build of scws + zhparser, layered on postgres:18
│   └── zhparser.sql        # Idempotent extension verification / smoke-test script
├── postgis/
│   └── Dockerfile          # scws + zhparser layered on postgis/postgis:18-3.6
├── .github/workflows/
│   ├── postgres-build.yml      # Builds & publishes the base image
│   ├── postgres-zhparser.yml   # Builds & publishes the zhparser image (+ smoke test)
│   └── postgres-postgis.yml    # Builds & publishes the postgis image (+ smoke test)
├── CODEBUDDY.md
├── AGENTS.md
└── README.md
```

## CI/CD

GitHub Actions build, smoke-test, and publish the images to `ghcr.io/vnobo/postgres` on push to `main`, on tags (`v*`), and on a monthly schedule. Pull requests build and run a smoke test (executing `zhparser.sql`) without publishing. Docker Hub publishing is optional and requires `DOCKER_USERNAME` / `DOCKER_PASSWORD` secrets.

## License

MIT
