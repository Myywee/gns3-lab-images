#!/bin/sh

set -eu

mkdir -p /var/log/nginx /run/nginx

if ! pgrep -f '/opt/exp3/vuln-app/app.py' >/dev/null; then
    nohup python3 /opt/exp3/vuln-app/app.py \
        >/var/log/exp3-flask.log 2>&1 &
fi

sleep 1
curl -fsS http://127.0.0.1:5000/healthz >/dev/null

nginx -t
if pgrep -x nginx >/dev/null; then
    nginx -s reload
else
    nginx
fi

echo 'exp3 started'
