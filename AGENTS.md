# This file provides guidance to CodeBuddy when working with code in this repository.

## Overview

This repository builds and publishes Docker images for PostgreSQL 18 with optional Chinese full-text search (`zhparser`)
and geospatial (`postgis`) extensions. Images are pushed to `ghcr.io/vnobo/postgres`. The README documents three
published tags: `18` (base), `18-zhparser`, and `18-postgis`.

## Architecture

The repository is a collection of independent Docker build contexts, each producing a layered PostgreSQL image. There is
no application code or test framework; everything is declarative Dockerfile/SQL. The key architectural idea is
**progressive extension layering** via multi-stage builds:

- **Base locale layer (`Dockerfile`)**: Starts from `postgres:18`. Its only real job is environment setup — links the
  timezone to `Asia/Shanghai` and generates `zh_CN`/`zh_HK`/`zh_TW` UTF-8 locales via `localedef`, then sets
  `LANG=zh_CN.utf8`. No extensions are compiled here; it is the thinnest image and the common ancestor for
  Chinese-locale needs.

- **`zhparser/` build context (`zhparser/Dockerfile`)**: This is the core extension builder. It uses a **two-stage
  build**:
    1. A `builder` stage based on `postgres:18` installs compile tooling (`build-essential`, `postgresql-server-dev-18`,
       `autoconf`, `libtool`, etc.), then compiles **scws** (a Chinese word-segmentation C library, pinned to branch
       `1.2.3`) from source, and then compiles **zhparser** (pinned to master) against the PostgreSQL server headers.
    2. A final runtime stage copies only the compiled artifacts into a clean `postgres:18` image: `zhparser.so`,
       `libscws.*`, the extension SQL/control files, the bitcode directory (for JIT), and the `.utf8` tsearch
       dictionaries. It also sets the `zh_CN.UTF-8` locale. This keeps the final image small and free of build
       toolchains.

- **`postgis/` build context (`postgis/Dockerfile`)**: Layers zhparser *on top of* the official `postgis/postgis:18-3.6`
  image rather than plain PostgreSQL. Its builder stage is nearly identical to `zhparser/` (same scws + zhparser compile
  steps) but starts from the PostGIS base, and the final stage copies the same zhparser artifacts into the PostGIS
  runtime image. PostGIS itself is already present in the base image, so this context only adds Chinese text search to
  an otherwise geospatial-enabled PostgreSQL.

The shared, copy-paste pattern across `zhparser/` and `postgis/` is deliberate: both compile the same scws+zhparser
artifacts and copy the same set of files (`zhparser.so`, `libscws.*`, `extension/zhparser*`, `bitcode/zhparser*`,
`tsearch_data/*.utf8.*`). When changing zhparser build behavior, edit both Dockerfiles in lockstep.

- **`zhparser/zhparser.sql`**: Not a build artifact but a manual verification script. It `CREATE EXTENSION zhparser`,
  registers a `chinese` text search configuration, inserts custom words into `zhparser.zhprs_custom_word`, synchronizes
  them, and runs `ts_debug`/`to_tsvector`/`to_tsquery` assertions against sample Chinese strings. Run it against a
  running `18-zhparser` or `18-postgis` container to confirm the extension works.

Build-time configuration is parameterized: `ARG PG_CONTAINER_VERSION=18` lets you retarget the PostgreSQL major version,
and `${PG_MAJOR}` (set by the upstream `postgres` image) is used throughout the `COPY --from=builder` paths so artifact
locations stay correct across PostgreSQL minors.

## Common Commands

### Build the base image (locale only)

```bash
docker build -t postgres:18 .
```

Builds the root `Dockerfile` producing a PostgreSQL 18 image with `zh_CN.UTF-8` locale and Asia/Shanghai timezone.
Override the tag as needed.

### Build the zhparser image

```bash
docker build -t postgres:18-zhparser ./zhparser
```

Multi-stage build compiling scws + zhparser from source, then assembling a runtime image with Chinese full-text search
enabled.

### Build the postgis image

```bash
docker build -t postgres:18-postgis ./postgis
```

Builds on `postgis/postgis:18-3.6` and adds the zhparser artifacts, yielding a geospatial + Chinese-search PostgreSQL
image.

### Pull published images

```bash
docker pull ghcr.io/vnobo/postgres:18
docker pull ghcr.io/vnobo/postgres:18-zhparser
docker pull ghcr.io/vnobo/postgres:18-postgis
```

Prebuilt images are hosted on GitHub Container Registry; pulling avoids a local source compile.

### Retarget PostgreSQL version

```bash
docker build --build-arg PG_CONTAINER_VERSION=18 -t postgres:18 ./zhparser
```

Use `--build-arg` to change the PostgreSQL major built into any image that defines `PG_CONTAINER_VERSION`.

### Verify the zhparser extension

```bash
docker run --rm -e POSTGRES_PASSWORD=test -p 5432:5432 postgres:18-zhparser &
psql -h localhost -U postgres -f zhparser/zhparser.sql
```

Starts a container, then runs `zhparser/zhparser.sql` to assert extension install, custom-word sync, and Chinese
text-search parsing behave correctly.
