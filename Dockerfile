FROM postgres:17

LABEL org.opencontainers.image.source=https://github.com/vnobo/docker-postgres.git
LABEL org.opencontainers.image.description=DESCRIPTION
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.title=TITLE
LABEL org.opencontainers.image.url=https://github.com/vnobo/docker-postgres.git
LABEL org.opencontainers.image.version=VERSION
LABEL org.opencontainers.image.created=CREATED
LABEL org.opencontainers.image.revision=REVISION

# 设置时区
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
RUN localedef -i zh_CN -c -f UTF-8 -A /usr/share/locale/locale.alias zh_CN.UTF-8
RUN localedef -i zh_HK -c -f UTF-8 -A /usr/share/locale/locale.alias zh_HK.UTF-8
RUN localedef -i zh_TW -c -f UTF-8 -A /usr/share/locale/locale.alias zh_TW.UTF-8 
ENV LANG=zh_CN.utf8
