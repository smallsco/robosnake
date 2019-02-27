#!/bin/sh

sed -i -e 's/$PORT/'"$PORT"'/g' /etc/nginx/conf.d/server.conf
exec /usr/local/openresty/bin/openresty -g "daemon off;"