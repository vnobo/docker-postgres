ARG PG_CONTAINER_VERSION=18
FROM postgres:${PG_CONTAINER_VERSION} AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN set -ex \
  && apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates postgresql-server-dev-${PG_MAJOR} pkg-config binutils automake libtool \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Build scws from the latest master (not pinned; builds are not reproducible).
RUN set -ex \
  && git init scws \
  && cd scws \
  && git remote add origin https://github.com/hightman/scws.git \
  && git fetch --depth 1 origin master \
  && git checkout FETCH_HEAD \
  && touch README && aclocal && autoconf && autoheader && libtoolize && automake --add-missing \
  && ./configure \
  && make install

# Build zhparser from the latest master (not pinned; builds are not reproducible).
RUN set -ex \
  && git init zhparser \
  && cd zhparser \
  && git remote add origin https://github.com/amutu/zhparser.git \
  && git fetch --depth 1 origin master \
  && git checkout FETCH_HEAD \
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
