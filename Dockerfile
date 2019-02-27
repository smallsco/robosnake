FROM openresty/openresty:1.13.6.2-alpine

# Replace default nginx config with Robosnake's config
COPY config/server.prod.conf /etc/nginx/conf.d/default.conf

# Copy the lua and static files to /var/luasnake
RUN mkdir -p /var/luasnake
WORKDIR /var/luasnake
COPY src/* ./

# Entrypoint for Heroku
CMD sed -i -e 's/XXPORTXX/'"$PORT"'/g' /etc/nginx/conf.d/default.conf && /usr/local/openresty/bin/openresty -g 'daemon off;'
