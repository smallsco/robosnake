#!/bin/sh

echo $PORT
sed -i "s/PORT/$PORT/g" /etc/nginx/conf.d/server.conf
exec /usr/local/openresty/bin/openresty -g "daemon off;"