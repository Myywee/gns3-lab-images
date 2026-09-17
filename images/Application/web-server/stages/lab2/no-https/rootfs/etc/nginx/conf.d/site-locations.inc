root /var/www/portal;
index index.html;

location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
}

location ~* \.(css|js)$ {
    try_files $uri =404;
    add_header Cache-Control "public, max-age=7200" always;
    access_log off;
}

location ~* \.(png|jpg|jpeg|gif|ico|svg|ttf|woff|woff2|eot)$ {
    try_files $uri =404;
    add_header Cache-Control "public, max-age=2592000" always;
    add_header Access-Control-Allow-Origin "*" always;
    access_log off;
}

location ~* \.pdf$ {
    try_files $uri =404;
    add_header Cache-Control "public, max-age=86400" always;
}

location ~* \.html$ {
    try_files $uri =404;
    add_header Cache-Control "no-store, no-cache, must-revalidate" always;
}

location / {
    try_files $uri $uri/ =404;
}
