ARG PG_CONTAINER_VERSION=18
FROM postgres:${PG_CONTAINER_VERSION} AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN set -ex \
  && apt-get update \
  && apt-get install -y --no-install-recommends build-essential git postgresql-server-dev-${PG_MAJOR} pkg-config binutils automake libtool \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Pin scws to the release 1.2.3 commit SHA for reproducible, supply-chain-safe builds.
# Bump this ARG to upgrade scws (see https://github.com/hightman/scws/releases).
ARG SCWS_COMMIT=a04ef5e655213eb6b07fb57761d0eac72c281ad4
RUN set -ex \
  && git init scws \
  && cd scws \
  && git remote add origin https://github.com/hightman/scws.git \
  && git fetch --depth 1 origin "${SCWS_COMMIT}" \
  && git checkout "${SCWS_COMMIT}" \
  && touch README && aclocal && autoconf && autoheader && libtoolize && automake --add-missing \
  && ./configure \
  && make install

# Pin zhparser to an explicit commit SHA for reproducible, supply-chain-safe builds.
# Bump this ARG to upgrade zhparser (see https://github.com/amutu/zhparser/commits/master).
ARG ZHPARSER_COMMIT=2e995c4df672563992b4d7a147b8fa2d0d4cda6c
RUN set -ex \
  && git init zhparser \
  && cd zhparser \
  && git remote add origin https://github.com/amutu/zhparser.git \
  && git fetch --depth 1 origin "${ZHPARSER_COMMIT}" \
  && git checkout "${ZHPARSER_COMMIT}" \
  && make install

FROM postgres:${PG_CONTAINER_VERSION}
RUN localedef -i zh_CN -c -f UTF-8 -A /usr/share/locale/locale.alias zh_CN.UTF-8
ENV LANG=zh_CN.UTF-8

LABEL org.opencontainers.image.source=https://github.com/vnobo/docker-postgres.git
LABEL org.opencontainers.image.description="Docker build postgresql database images,text search support chinese zhparser extension."
LABEL org.opencontainers.image.licenses=MIT

COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/zhparser.so /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=builder /usr/local/lib/libscws.* /usr/local/lib/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/zhparser* /usr/share/postgresql/${PG_MAJOR}/extension/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/zhparser* /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/tsearch_data/*.utf8.* /usr/share/postgresql/${PG_MAJOR}/tsearch_data/
# Refresh the dynamic linker cache so zhparser.so can find libscws at runtime.
RUN ldconfig
