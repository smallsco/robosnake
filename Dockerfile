FROM openresty/openresty:1.13.6.2-alpine

# Remove default nginx config and install Robosnake's config
COPY config/http.conf /etc/nginx/conf.d/
COPY config/server.prod.conf /etc/nginx/conf.d/default.conf

# Copy the lua and static files to /var/luasnake
RUN mkdir -p /var/luasnake
WORKDIR /var/luasnake
COPY src/* ./

CMD sed -i -e 's/PORT/'"$PORT"'/g' /etc/nginx/conf.d/default.conf && /usr/local/openresty/bin/openresty -g 'daemon off;'
