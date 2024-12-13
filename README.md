# postgres

Docker build postgresql database images , text search support chinese zhparser extension and postgis extension

## Postgresql 17

### Docker build postgresql 17 image with postgres:17

Set lang is zh_CN.UTF-8

See [Postgres Dockerfile](./Dockerfile)

<p></p>

#### Get Docker Image

```bash
docker pull ghcr.io/vnobo/postgres:17
```

## Postgresql 17 with zhparser

### Docker build postgresql 17 image with postgres:17-bookworm

1. add build postgresql zhparser extension
2. set lang is zh_CN.UTF-8

See [Postgres Zhparser Dockerfile](./zhparser/Dockerfile)

Get Docker Image

```bash
docker pull ghcr.io/vnobo/postgres:17-zhparser
```

## Postgresql 17 with postgis

### Docker build postgresql 17 image with postgis:17-master

1. add postgresql postgis extension
2. add postgresql zhparser extension
3. set lang is zh_CN.UTF-8

See [Postgres Postgis Dockerfile](./postgis/Dockerfile)

Get Docker Image

```bash
docker pull ghcr.io/vnobo/postgres:17-postgis
```