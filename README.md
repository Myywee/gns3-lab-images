# GNS3 lab images

This repository contains the container images used by the GNS3 networking
labs. Every experiment image is built on the shared toolbox base; individual
labs add only their stage-specific configuration and behaviour.

## Shared toolbox base

`images/toolbox` is the foundational device for all experiments in this
repository, not a Lab 1-specific image. It consolidates the Ubuntu runtime,
service packages, and CLI and network-diagnostic tools that experiment images
share. New lab images should inherit this base and only add or override the
files required by that lab.

The `gns3-lab/toolbox:lab1` tag used below is the tag currently consumed by
the Lab 1 Dockerfiles; it does not limit the toolbox build context to Lab 1.

## Lab 1 image matrix

| Role | Variant | Intended behaviour |
| --- | --- | --- |
| web-server | `vulnerable` | `/secure/` and the exposed `/.git/` repository are directly readable |
| web-server | `complete` | Nginx internal resources and dotfiles are protected |
| dns-server | `no-recursion` | Authoritative for `experiment.test`; recursive service is disabled |
| dns-server | `complete` | Authoritative plus recursive and caching service for lab clients |
| client | `no-cache` | Inherited `dnsmasq-base` is explicitly removed; no local cache is installed |
| client | `complete` | A local `dnsmasq-base` cache listens on `127.0.0.1:53` |

## Lab 2 image matrix

| Role | Variant | Intended behaviour |
| --- | --- | --- |
| dns-server | `complete` | Retains the Lab 1 authoritative and recursive service, and overrides `networking-experiments.nju-slab.cn` to `10.10.20.20` with a separate authoritative zone |
| web-server | `no-https` | Represents the end of Lab 2 step 4: persistent homepage, HTTP nginx, cache policy and image/font CORS, before DNS override and HTTPS |
| web-server | `complete` | Extends `no-https` with HTTPS and an HTTP 301 redirect; TLS files are supplied only through a read-only host bind mount |

Application variant build contexts follow the same shape:

```text
<image>/
├── Dockerfile
├── rootfs/
├── [image-specific resources]
└── tests/
    └── smoke.sh
```

The toolbox keeps the same `Dockerfile` and `tests/` convention, and only
needs a `rootfs/` overlay when a future experiment adds shared files. The
bracketed entry is optional; Lab 2's web image uses `resources/homepage.tar`.

The former `images/ubuntu` build context has been consolidated into the shared
`images/toolbox` base. Lab 1 application variants under
`images/Application/<role>/stages/lab1/<variant>/` inherit that base through
the `gns3-lab/toolbox:lab1` tag. The no-cache client removes `dnsmasq-base`
again so the intended package-level difference remains observable.

## Build

Build the project-wide toolbox first, then the desired experiment variants:

```sh
docker build -t gns3-lab/toolbox:lab1 images/toolbox

docker build -t gns3-lab/web-server:lab1-vulnerable \
  images/Application/web-server/stages/lab1/vulnerable
docker build -t gns3-lab/web-server:lab1-complete \
  images/Application/web-server/stages/lab1/complete

docker build -t gns3-lab/dns-server:lab1-no-recursion \
  images/Application/dns-server/stages/lab1/no-recursion
docker build -t gns3-lab/dns-server:lab1-complete \
  images/Application/dns-server/stages/lab1/complete

docker build -t gns3-lab/client:lab1-no-cache \
  images/Application/client/stages/lab1/no-cache
docker build -t gns3-lab/client:lab1-complete \
  images/Application/client/stages/lab1/complete

docker build -t gns3-lab/dns-server:lab2-complete \
  images/Application/dns-server/stages/lab2/complete
docker build \
  --build-arg BASE_IMAGE=gns3-lab/web-server:lab1-complete \
  -t gns3-lab/web-server:lab2-no-https \
  images/Application/web-server/stages/lab2/no-https
docker build \
  --build-arg BASE_IMAGE=gns3-lab/web-server:lab2-no-https \
  -t gns3-lab/web-server:lab2-complete \
  images/Application/web-server/stages/lab2/complete
```

Run all Lab 1 build-and-runtime checks with:

```sh
images/tests/smoke-lab1.sh
```

Run the Lab 2 DNS build-and-runtime check with:

```sh
images/Application/dns-server/stages/lab2/complete/tests/smoke.sh
```

Run the Lab 2 web build-and-runtime check with:

```sh
images/Application/web-server/stages/lab2/no-https/tests/smoke.sh
images/Application/web-server/stages/lab2/complete/tests/smoke.sh
```

Each image's `tests/smoke.sh` can also be run independently. The DNS complete
test uses an isolated synthetic root server, so recursion and cache reuse are
tested without Internet access. To exercise a previously built image without
rebuilding it, set `SKIP_TOOLBOX_BUILD=1`, `SKIP_IMAGE_BUILD=1`, and point
`TOOLBOX_IMAGE`/`IMAGE_TAG` at the existing tags.

The Lab 2 DNS image inherits `gns3-lab/dns-server:lab1-complete`, so build the
Lab 1 complete DNS image first. Its smoke test builds that dependency by
default and verifies that both the Lab 1 and Lab 2 zones remain authoritative.
The Lab 2 `no-https` web image similarly inherits
`gns3-lab/web-server:lab1-complete` and preserves a copy of the inherited
nginx configuration under `/opt/gns3-labs/lab1-nginx-backup`. The Lab 2
`complete` web image then inherits `no-https`; its smoke test can reuse an
existing local base by setting `SKIP_NO_HTTPS_BUILD=1` and
`NO_HTTPS_IMAGE_TAG`.

## Runtime configuration

The images do not bring interfaces up or configure interface addresses or
default routes. Configure those values for each topology node with its **Start
command** in GNS3. Application startup scripts leave that GNS3-provided
network state unchanged; the two client variants only select whether
`/etc/resolv.conf` uses the local cache or the experiment BIND server directly.

If a GNS3 Start command replaces an image's default command, that Start
command must also launch the required application service, or the service must
be started manually as part of the experiment.

The complete client follows the Lab 1 cache path exactly: `/etc/resolv.conf`
points to `127.0.0.1`, and `/etc/dnsmasq.d/lab-cache.conf` forwards only to the
experiment BIND server at `10.10.20.10`. The no-cache variant points
`/etc/resolv.conf` directly to `10.10.20.10` and does not contain the dnsmasq
binary.

The `experiment.test` zone follows the Lab 1 topology: `ns1` resolves to the
DNS server at `10.10.20.10`, while the zone apex and `www` resolve to the web
server at `10.10.20.20`.

### Lab 2 no-HTTPS web resources

The Lab 2 `no-https` web image contains the state reached after completing
steps 1-4 of the experiment guide. It serves the portal over HTTP with the
required cache and CORS rules; it does not configure HTTPS or require
certificate files.

| Resource | Storage | Container path |
| --- | --- | --- |
| `resources/homepage.tar` | Checked into the Lab 2 web build context and copied into the image | `/opt/gns3-labs/lab2/homepage.tar` |
| Extracted homepage | GNS3 project persistent volume | `/var/www/portal` |

The supplied archive contains a top-level `homepage/` directory. On the first
start with an empty `/var/www/portal`, the startup script removes that one path
component while extracting it and records the archive checksum in
`.gns3-homepage-source`. Later starts preserve everything in the persistent
volume. To reseed it from a newer image, clear that project volume before
starting the container.

For example, when invoking Docker on the GNS3 VM directly:

```sh
docker run --detach \
  --mount type=volume,src=lab2-portal,dst=/var/www/portal \
  gns3-lab/web-server:lab2-no-https \
  /usr/local/lib/gns3/start-web-server.sh
```

The server listens only on port 80. Certificate import and the port 443 server
belong to the later HTTPS extension steps and are intentionally absent from
this variant.

### Lab 2 complete HTTPS web server

The `lab2-complete` image adds the port 443 virtual host and redirects HTTP to
HTTPS. Neither the certificate nor the private key is copied into the build
context or image. Keep both files on the GNS3 VM (the Docker host) and expose
them to the container through a read-only bind mount.

The host directory must contain these exact names:

| Host file | Container path |
| --- | --- |
| `networking-experiments.nju-slab.cn.fullchain.pem` | `/etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem` |
| `networking-experiments.nju-slab.cn.key` | `/etc/nginx/certs/networking-experiments.nju-slab.cn.key` |

Prepare the host directory without placing it below this repository. The
private key must have mode `0600` or `0400`:

```sh
install -d -m 0700 /opt/gns3-lab-secrets/lab2-web
install -m 0644 /secure/source/networking-experiments.nju-slab.cn.fullchain.pem \
  /opt/gns3-lab-secrets/lab2-web/
install -m 0600 /secure/source/networking-experiments.nju-slab.cn.key \
  /opt/gns3-lab-secrets/lab2-web/
```

For a direct Docker launch on the GNS3 VM:

```sh
docker run --detach \
  --name lab2-web-server \
  --mount type=volume,src=lab2-portal,dst=/var/www/portal \
  --mount type=bind,src=/opt/gns3-lab-secrets/lab2-web,dst=/etc/nginx/certs,readonly \
  gns3-lab/web-server:lab2-complete \
  /usr/local/lib/gns3/start-web-server.sh
```

When GNS3 manages the container, configure the equivalent host path,
`/etc/nginx/certs` container path, and read-only option in the Docker template.
Use `/usr/local/lib/gns3/start-web-server.sh` as the Start command after any
topology-specific network setup. The startup script fails closed if the mount
is missing or writable, either required file is missing, or the key mode is too
permissive. It then runs `nginx -t`, which also rejects a mismatched certificate
and key.
