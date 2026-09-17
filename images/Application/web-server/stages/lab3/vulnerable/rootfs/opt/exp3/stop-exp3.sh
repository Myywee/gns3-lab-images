#!/bin/sh

nginx -s quit 2>/dev/null || true
pkill -f '/opt/exp3/vuln-app/app.py' 2>/dev/null || true
echo 'exp3 stopped'
