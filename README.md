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

Application variant build contexts follow the same shape:

```text
<image>/
├── Dockerfile
├── rootfs/
└── tests/
    └── smoke.sh
```

The toolbox keeps the same `Dockerfile` and `tests/` convention, and only
needs a `rootfs/` overlay when a future experiment adds shared files.

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
```

Run all build-and-runtime checks with:

```sh
images/tests/smoke-lab1.sh
```

Each image's `tests/smoke.sh` can also be run independently. The DNS complete
test uses an isolated synthetic root server, so recursion and cache reuse are
tested without Internet access. To exercise a previously built image without
rebuilding it, set `SKIP_TOOLBOX_BUILD=1`, `SKIP_IMAGE_BUILD=1`, and point
`TOOLBOX_IMAGE`/`IMAGE_TAG` at the existing tags.

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
