# Lab 3 vulnerable web server (middle checkpoint)

This image is the Lab 3 middle checkpoint. It replaces the Lab 2 portal with
the two HTTPS virtual hosts used by the XSS and CSRF exercise:

- `networking-experiments.nju-slab.cn` proxies to the deliberately vulnerable
  Flask application on `127.0.0.1:5000`.
- `networking-experiments-2.nju-slab.cn` serves the simulated attacker page.

The Flask application deliberately contains reflected and stored XSS, exposes
its session cookie to JavaScript, and accepts password changes without a CSRF
token. Use it only in the authorized, isolated GNS3 lab.

Like the Lab 2 image, this image starts with `/bin/bash`; it does not
automatically validate mounts or launch Flask and nginx. The Lab 2 certificate
and key remain external to the image. Mount their host directory at
`/etc/nginx/certs`; it must contain:

- `networking-experiments.nju-slab.cn.fullchain.pem`
- `networking-experiments.nju-slab.cn.key`

The certificate SAN must cover both experiment hostnames. Mode `0400` or
`0600` is recommended for the private key.

```sh
docker run --rm -it \
  --name lab3-vulnerable-web-server \
  --mount type=bind,src=/opt/gns3-lab-secrets/lab2-web,dst=/etc/nginx/certs,readonly \
  gns3-lab/web-server:lab3-vulnerable
```

After entering the container or GNS3 node, start the experiment services when
needed:

```sh
/opt/exp3/start-exp3.sh
```

For a GNS3 Docker template, retain the image default `/bin/bash` Start command.
