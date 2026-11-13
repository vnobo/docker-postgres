# postgres

> Also available in [中文](./README_zh.md).

Docker images for **PostgreSQL 18** with optional **Chinese full-text search** ([`zhparser`](https://github.com/amutu/zhparser)) and **geospatial** ([PostGIS](https://postgis.net)) extensions. All images set the system locale to `zh_CN.UTF-8` and the timezone to `Asia/Shanghai`.

Images are published to GitHub Container Registry, and optionally to Docker Hub when `DOCKER_USERNAME` / `DOCKER_PASSWORD` repository secrets are configured:

| Tag                                     | Base image               | Extensions                | Description                                                                                                                         |
|-----------------------------------------|--------------------------|---------------------------|-------------------------------------------------------------------------------------------------------------------------------------|
| `ghcr.io/vnobo/postgres:18`             | `postgres:18`            | —                         | PostgreSQL 18 with `zh_CN.UTF-8` locale and `Asia/Shanghai` timezone.                                                               |
| `ghcr.io/vnobo/postgres:18-zhparser`    | `postgres:18`            | zhparser + scws           | Adds Chinese full-text search.                                                                                                      |
| `ghcr.io/vnobo/postgres:18-postgis`     | `postgis/postgis:18-3.6` | PostGIS + zhparser + scws | Geospatial + Chinese full-text search.                                                                                              |
| `ghcr.io/vnobo/postgres:latest-postgis` | `postgis/postgis:18-3.6` | PostGIS + zhparser + scws | Rolling `latest` alias of the most recent `18-postgis` build (pushed on every `main`/tag build). **Not for pinned production use.** |

## Target audience & use cases

- **Ops / decision makers**: want a ready-made PostgreSQL 18 Chinese environment, or evaluating whether this repo fits —
  read the image table and selection guide.
- **Application developers**: need Chinese full-text search (license plates, addresses, product names, etc.) — use
  `18-zhparser` or `18-postgis`.
- **Build / maintenance**: change images, upgrade dependencies, or understand CI publishing — read "Build from source /
  CI/CD".

## Image selection

| Your need                                      | Recommended tag                                               |
|------------------------------------------------|---------------------------------------------------------------|
| PostgreSQL 18 + Chinese locale / timezone only | `:18`                                                         |
| Chinese full-text search (no geospatial)       | `:18-zhparser`                                                |
| Chinese search + geospatial queries            | `:18-postgis`                                                 |
| Always the latest postgis build (rolling)      | `:latest-postgis` (not recommended for pinned production use) |

## Prerequisites

- Docker installed (24+ recommended; supports multi-stage builds and pulling from `ghcr.io`).
- Access to `ghcr.io` (to pull prebuilt images) or a build environment (to build from source).
- A client to connect: `psql` (PostgreSQL client) or `docker exec` inside the container.

## Tech stack & pinned versions

| Component   | Version         | Source                                              | Notes                                                                                        |
|-------------|-----------------|-----------------------------------------------------|----------------------------------------------------------------------------------------------|
| PostgreSQL  | 18              | `postgres:18`                                       | Floating to latest 18.x patch (security).                                                    |
| PostGIS     | 3.6 (3.6.0)     | `postgis/postgis:18-3.6`                            | Requires PostgreSQL 12–18.                                                                   |
| scws (SCWS) | 1.2.3 (`a04ef5e`) | [hightman/scws](https://github.com/hightman/scws) | Chinese word-segmentation C library; pinned to the 1.2.3 release commit because upstream `master` fails to build under the automake in the base image. |
| zhparser    | master (latest) | [amutu/zhparser](https://github.com/amutu/zhparser) | Built from latest `master`; not pinned, so builds are not reproducible or supply-chain safe. |

> **Upgrading:** scws is pinned to the 1.2.3 release commit (its `master` is broken under current automake); zhparser tracks upstream `master` HEAD. To change either, edit the relevant `ARG`/fetch in [`zhparser/Dockerfile`](./zhparser/Dockerfile) and [`postgis/Dockerfile`](./postgis/Dockerfile).

## Quick start

### Pull a prebuilt image

```bash
docker pull ghcr.io/vnobo/postgres:18
docker pull ghcr.io/vnobo/postgres:18-zhparser
docker pull ghcr.io/vnobo/postgres:18-postgis
```

### Run with Chinese search enabled

Persist data with a named volume so it survives container removal:

```bash
docker run --name pg \
  -e POSTGRES_PASSWORD=secret \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  -d ghcr.io/vnobo/postgres:18-zhparser
```

Enable the extension, then create the `chinese` text search configuration and try the segmentation examples
in [Chinese full-text search in practice](#chinese-full-text-search-in-practice):

```sql
CREATE EXTENSION IF NOT EXISTS zhparser;
```

## Chinese full-text search in practice

`zhparser` is built on the [scws](https://github.com/hightman/scws) segmenter: it splits Chinese text into **lexemes**
(词元), which PostgreSQL then indexes as `tsvector` and matches with `tsquery`. Unlike English, Chinese has no
whitespace word boundaries, so a parser must decide where words start and end — and that is exactly where mixed content
(Chinese + letters + digits, e.g. license plates) gets tricky.

> **Note:** the `to_tsvector` / `ts_debug` lexemes and `ST_DistanceSphere` distances below are **illustrative outputs,
> not verified by a real run** — trust your own environment (validate with [
> `zhparser/zhparser.sql`](./zhparser/zhparser.sql)).

### Case 1 — plain license plate

A plate like `京A12345` mixes a Chinese character, a Latin letter and digits. zhparser tokenizes it as a single unit:

```sql
select to_tsvector('chinese', '京A12345');
-- '京a12345':1
```

### Case 2 — plate embedded in a Chinese address

When a plate is part of a longer string, the surrounding Chinese is segmented independently:

```sql
select to_tsvector('chinese', '北京市海淀区京A12345违法记录');
-- '北京':1 '北京市':2 '海淀区':3 '京a12345':4 '违法':5 '记录':6
```

### Case 3 — register a custom word so a plate prefix is kept whole

By default the province letter (`京A`, `沪B` …) may be broken apart. Register it as a custom word and resync so it is
always treated as one lexeme:

```sql
insert into zhparser.zhprs_custom_word
values ('京A'),
       ('沪B');
select sync_zhprs_custom_word();
alter extension zhparser update;
```

After syncing, re-running Case 2 keeps `京A` intact and makes plate-prefix searches reliable. Inspect the split
before/after with `ts_debug`:

```sql
-- before custom word: the province prefix may be broken apart
select ts_debug('chinese', '京A12345违法记录');
-- after registering '京A' and sync_zhprs_custom_word(): '京A' is one lexeme
```

### Combined: Chinese segmentation + PostGIS (geospatial search)

On the `18-postgis` image you can index Chinese text **and** geometry, then query both at once — e.g. "find vehicles
whose plate/address matches a keyword and that are within 50 km of a point":

```sql
-- on ghcr.io/vnobo/postgres:18-postgis
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS zhparser;

DROP TEXT SEARCH CONFIGURATION IF EXISTS chinese;
CREATE TEXT SEARCH CONFIGURATION chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION chinese ADD MAPPING FOR n,v,a,i,e,l,x WITH simple;

CREATE TABLE vehicles
(
    id       serial PRIMARY KEY,
    plate    text,                 -- license plate, e.g. '京A12345'
    address  text,                 -- Chinese address
    location geometry(Point, 4326) -- lon/lat
);

-- auto-maintained Chinese search vector (PostgreSQL 12+ generated column)
ALTER TABLE vehicles
    ADD COLUMN search tsvector
        GENERATED ALWAYS AS (
            to_tsvector('chinese', coalesce(plate, '') || ' ' || coalesce(address, ''))
            ) STORED;

CREATE INDEX vehicles_search_gin ON vehicles USING gin (search);
CREATE INDEX vehicles_loc_gist ON vehicles USING gist (location);

INSERT INTO vehicles (plate, address, location)
VALUES ('京A12345', '北京市海淀区中关村南大街', ST_SetSRID(ST_MakePoint(116.316, 39.983), 4326)),
       ('沪B67890', '上海市浦东新区世纪大道', ST_SetSRID(ST_MakePoint(121.505, 31.239), 4326));

-- keyword match + spatial filter (within 50 km of central Beijing)
SELECT plate,
       address,
       ST_DistanceSphere(
               location,
               ST_SetSRID(ST_MakePoint(116.40, 39.90), 4326)
       ) AS dist_m
FROM vehicles
WHERE search @@ to_tsquery('chinese', '北京')
  AND ST_DWithin(
        location::geography,
        ST_SetSRID(ST_MakePoint(116.40, 39.90), 4326)::geography,
        50000
      );
--  plate   | address                  | dist_m
-- ---------+--------------------------+---------
--  京A12345 | 北京市海淀区中关村南大街 | ~7800
```

The `GIN` index accelerates the `@@` full-text match; the `GiST` index accelerates the `ST_DWithin` spatial filter. Use
`::geography` for meter-accurate distances.

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
├── README.md               # This file (English)
├── README_zh.md            # Chinese translation
└── AGENTS.md
```

## CI/CD

GitHub Actions build, smoke-test, and publish the images to `ghcr.io/vnobo/postgres` on push to `main`, on tags (`v*`),
and on a monthly schedule. Pull requests build and run a smoke test (executing `zhparser.sql`) without publishing. All
three workflows also support **manual runs** via `workflow_dispatch` (Actions → *Run workflow*). Docker Hub publishing
is optional and requires `DOCKER_USERNAME` / `DOCKER_PASSWORD` secrets.

## FAQ

- **Auth failure / `role "postgres" does not exist`**: start with `-e POSTGRES_PASSWORD=...` and connect with
  `psql -U postgres -h localhost` using that password.
- **`CREATE EXTENSION zhparser` not found**: use the `18-zhparser` or `18-postgis` image (the base `:18` does not
  include the extension).
- **Chinese search returns nothing**: make sure the `chinese` configuration is created with `ADD MAPPING` (see practice
  section) and query with `to_tsquery('chinese', ...)` rather than a plain string.
- **Data lost when container is removed**: add `-v <volume>:/var/lib/postgresql/data` at runtime (see Quick start).

## Acknowledgements

These images build on the work of several open-source projects:

- [PostgreSQL](https://www.postgresql.org) — the database engine and official `postgres` base images.
- [PostGIS](https://postgis.net) — geospatial extension and the `postgis/postgis` base images.
- [scws (SCWS)](https://github.com/hightman/scws) — Chinese word-segmentation C library that zhparser depends on.
- [zhparser](https://github.com/amutu/zhparser) — PostgreSQL Chinese full-text parser.

Thanks to their maintainers and contributors.

## License

MIT
