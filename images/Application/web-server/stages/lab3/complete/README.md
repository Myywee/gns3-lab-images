# Lab 3 complete web server

This image extends `lab3-vulnerable` with the final application state from the
Lab 3 guide:

- reflected and stored XSS output is escaped;
- the session cookie uses `Secure`, `HttpOnly`, and `SameSite=Lax`;
- password changes require a 64-character per-session CSRF token;
- login and successful password changes rotate the CSRF token;
- missing, invalid, and replayed tokens return HTTP 403.

The simulated attacker site remains available so its tokenless form can be
used to verify that the completed application rejects the request.

Like the middle checkpoint and Lab 2, the container starts with `/bin/bash` and
does not automatically launch the services. Use the same read-only
`/etc/nginx/certs` host bind mount documented by the middle checkpoint:

```sh
docker run --rm -it \
  --name lab3-complete-web-server \
  --mount type=bind,src=/opt/gns3-lab-secrets/lab2-web,dst=/etc/nginx/certs,readonly \
  gns3-lab/web-server:lab3-complete
```

Start Flask and nginx explicitly after entering the node:

```sh
/opt/exp3/start-exp3.sh
```
