ARG NGINX_VERSION=1.16.0
ARG BUILD_PATH=/build

FROM nginx:${NGINX_VERSION} as build

RUN apt-get update \
    && apt-get install -y --no-install-suggests \
       wget curl \
       lua5.1 liblua5.1-0 liblua5.1-dev \
       libluajit-5.1-2 libluajit-5.1-dev \
       zlib1g-dev libpcre3-dev \
       libexpat1-dev git curl build-essential libxml2 libxslt1.1 libxslt1-dev autoconf libtool libssl-dev

ARG NGINX_VERSION
ARG BUILD_PATH
ARG NDK_VERSION=0.3.1rc1
ARG LUA_NGX_VERSION=0.10.15
ARG DAV_EXT_VERSION=3.0.0

RUN mkdir --verbose -p ${BUILD_PATH}
WORKDIR $BUILD_PATH

ADD get-src /usr/bin
RUN get-src 4fd376bad78797e7f18094a00f0f1088259326436b537eb5af69b01be2ca1345 \
        "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" && \
    get-src 49f50d4cd62b166bc1aaf712febec5e028d9f187cedbc27a610dfd01bdde2d36 \
        "https://github.com/simpl/ngx_devel_kit/archive/v$NDK_VERSION.tar.gz" && \
    get-src 7d5f3439c8df56046d0564b5857fd8a30296ab1bd6df0f048aed7afb56a0a4c2 \
        "https://github.com/openresty/lua-nginx-module/archive/v$LUA_NGX_VERSION.tar.gz" && \
    get-src d2499d94d82d4e4eac8425d799e52883131ae86a956524040ff2fd230ef9f859 \
        "https://github.com/arut/nginx-dav-ext-module/archive/v$DAV_EXT_VERSION.tar.gz"

RUN ln -s /usr/lib/x86_64-linux-gnu/liblua5.1.so /usr/lib/liblua.so; \
    ln -s /usr/lib/x86_64-linux-gnu /usr/lib/lua-platform-path

ENV LUAJIT_LIB="/usr/lib/x86_64-linux-gnu"
ENV LUAJIT_INC="/usr/include/luajit-2.0"

# Build nginx
WORKDIR ${BUILD_PATH}/nginx-${NGINX_VERSION}
RUN CONFIGURE_ARGS="$(nginx -V 2>&1 | grep "configure arguments:" | awk -F 'configure arguments:' '{print $2}')"; \
    /bin/bash -c './configure --with-compat ${CONFIGURE_ARGS} \
        --add-dynamic-module=$BUILD_PATH/ngx_devel_kit-$NDK_VERSION \
        --add-dynamic-module=$BUILD_PATH/lua-nginx-module-$LUA_NGX_VERSION \
        --add-dynamic-module=$BUILD_PATH/nginx-dav-ext-module-$DAV_EXT_VERSION'

RUN make modules && mkdir $BUILD_PATH/modules && mv objs/*.so $BUILD_PATH/modules

FROM nginx:${NGINX_VERSION}
ARG NGINX_VERSION
ARG BUILD_PATH
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
apt-get install --no-install-recommends --no-install-suggests -y \
  curl \
  ca-certificates \
  libcurl4-openssl-dev \
  libyajl-dev \
  lua5.1-dev \
  luarocks \
  libluajit-5.1-2 libluajit-5.1-dev \
  libxml2 libcap2-bin && \
  rm -rf /var/lib/apt/lists/*

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/lib/x86_64-linux-gnu/liblua5.1.so /usr/lib/liblua.so; \
    ln -s /usr/lib/x86_64-linux-gnu /usr/lib/lua-platform-path

ENV LUAJIT_LIB="/usr/lib/x86_64-linux-gnu"
ENV LUAJIT_INC="/usr/include/luajit-2.0"

# Copy Over Modules
COPY --from=build ${BUILD_PATH}/modules* /usr/lib/nginx/modules/

RUN rm -f /etc/nginx/modules/all.conf && \
    ls /etc/nginx/modules/*.so | grep -v debug | xargs -I{} sh -c 'echo "load_module {};" | tee -a  /etc/nginx/modules/all.conf'

# Setup davt
RUN luarocks install ljsyscall

ADD rootfs/ /
ADD davt.lua /etc/nginx/scripts/davt.lua
EXPOSE 80

CMD ["/bin/bash", "/run.sh"]
