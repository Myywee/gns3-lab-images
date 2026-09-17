# Lab 2 complete web server

This image extends `lab2-no-https` with HTTPS and an HTTP-to-HTTPS redirect.
TLS material is deliberately absent from the build context and image. The two
required files must be stored on the GNS3 VM (the Docker host) and mounted into
the container as a read-only directory:

| Host file name | Container path |
| --- | --- |
| `networking-experiments.nju-slab.cn.fullchain.pem` | `/etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem` |
| `networking-experiments.nju-slab.cn.key` | `/etc/nginx/certs/networking-experiments.nju-slab.cn.key` |

Use mode `0644` (or stricter) for the full chain and mode `0600` or `0400` for
the private key on the host. For a direct Docker launch on the GNS3 VM:

```sh
docker run --detach \
  --mount type=volume,src=lab2-portal,dst=/var/www/portal \
  --mount type=bind,src=/opt/gns3-lab-secrets/lab2-web,dst=/etc/nginx/certs,readonly \
  gns3-lab/web-server:lab2-complete \
  /usr/local/lib/gns3/start-web-server.sh
```

Configure the equivalent `/etc/nginx/certs` read-only bind mount in the GNS3
Docker template when GNS3 owns the container lifecycle. Set its Start command
to `/usr/local/lib/gns3/start-web-server.sh`. Startup intentionally fails if
the mount is absent, writable, empty, or contains an overly permissive private
key.
