ARG PG_CONTAINER_VERSION=17
FROM postgis/postgis:${PG_CONTAINER_VERSION}-master AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN set -ex \
  && apt-get update \
  && apt-get install -y build-essential git postgresql-server-dev-${PG_MAJOR} pkg-config binutils automake libtool \
  && apt-get clean

RUN set -ex \
  && git clone --branch 1.2.3 --single-branch --depth 1 https://github.com/hightman/scws.git \
  && cd scws \
  && touch README;aclocal;autoconf;autoheader;libtoolize;automake --add-missing \
  && ./configure \
  && make install

RUN set -ex \
  && git clone --branch master --single-branch --depth 1 https://github.com/amutu/zhparser.git \
  && cd zhparser \
  && make install

FROM postgis/postgis:${PG_CONTAINER_VERSION}-master
RUN localedef -i zh_CN -c -f UTF-8 -A /usr/share/locale/locale.alias zh_CN.UTF-8
ENV LANG=zh_CN.UTF-8

LABEL org.opencontainers.image.source=https://github.com/vnobo/docker-postgres.git
LABEL org.opencontainers.image.description="Docker build postgresql database images,text search support chinese zhparser extension and postgis extension"
LABEL org.opencontainers.image.licenses=MIT

COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/zhparser.so /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=builder /usr/local/lib/libscws.* /usr/local/lib/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/zhparser* /usr/share/postgresql/${PG_MAJOR}/extension/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/zhparser* /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/tsearch_data/*.utf8.* /usr/share/postgresql/${PG_MAJOR}/tsearch_data/

