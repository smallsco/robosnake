#!/bin/sh

echo $PORT
cat /etc/nginx/conf.d/server.conf
sed -i "s/PORT/$PORT/g" /etc/nginx/conf.d/server.conf
cat /etc/nginx/conf.d/server.conf
exec /usr/local/openresty/bin/openresty -g "daemon off;"