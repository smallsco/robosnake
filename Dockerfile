#FROM openresty/openresty:1.13.6.2-alpine
FROM openresty/openresty:1.13.6.2-bionic

# Remove default nginx config and install Robosnake's config
RUN rm -f /etc/nginx/conf.d/default.conf
COPY config/http.conf /etc/nginx/conf.d/
COPY config/server.prod.conf /etc/nginx/conf.d/server.conf

# Copy the lua and static files to /var/luasnake
RUN mkdir -p /var/luasnake
WORKDIR /var/luasnake
COPY src/* ./
COPY docker-entrypoint.sh ./

