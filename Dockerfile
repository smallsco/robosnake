# Using this base image because of: https://github.com/openresty/docker-openresty/issues/124
FROM openresty/openresty:1.15.8.1-4-alpine

# Replace default nginx config with Robosnake's config
COPY config/server.prod.conf /etc/nginx/conf.d/default.conf

# Copy the lua and static files to /var/luasnake
RUN mkdir -p /var/luasnake
WORKDIR /var/luasnake
COPY src/* ./

# Entrypoint for Heroku
CMD /usr/local/openresty/bin/openresty -g 'daemon off;'
