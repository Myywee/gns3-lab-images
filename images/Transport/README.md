# Transport images

## Lab 6: TCP and UDP Socket Echo

Lab 6 adds two `complete` images built directly from
`ghcr.io/myywee/ubuntu:basic`:

- `client/stages/lab6/complete` contains `tcp_echo_client.py`,
  `udp_echo_client.py`, and `udp_peer.py`;
- `server/stages/lab6/complete` contains `tcp_echo_server.py`,
  `udp_echo_server.py`, and `udp_peer.py`.

All programs are installed as executable files in `/opt/socket-lab`, which is
also the default working directory. The images verify that Python 3,
`iproute2`, `ping`, and `tcpdump` are already available from the base image;
they do not install packages at build time and require no Internet access
during the experiment.

Build the images from the repository root:

```sh
docker build -t gns3-lab/transport-client:lab6-complete \
  images/Transport/client/stages/lab6/complete
docker build -t gns3-lab/transport-server:lab6-complete \
  images/Transport/server/stages/lab6/complete
```

Run their build-and-runtime smoke tests with:

```sh
images/Transport/client/stages/lab6/complete/tests/smoke.sh
images/Transport/server/stages/lab6/complete/tests/smoke.sh
```

Both images retain an interactive Bash default. Configure `eth0` with the Lab
6 GNS3 Start command, then start the TCP and UDP servers from the Server
console as described in the experiment guide. TCP and UDP can listen on port
18080 simultaneously. The peer program uses UDP/19001 on Client and UDP/19002
on Server.

## Lab 4: TCP congestion control

Lab 4 uses two `complete` images built directly from
`ghcr.io/myywee/ubuntu:basic`:

- `client/stages/lab4/complete`: the iperf3 sender and `ss` sampling node;
- `server/stages/lab4/complete`: the iperf3 receiver, exposing TCP port 5201.

The toolbox base already provides the three packages required by the lab:
`iperf3`, `iproute2`, and `tcpdump`. The Dockerfiles verify those packages and
the `/gns3/bin/busybox` helper at build time. They deliberately do not change
interfaces, routes, qdiscs, kernel modules, or host congestion-control
settings.

Build the images from the repository root:

```sh
docker build -t gns3-lab/transport-client:lab4-complete \
  images/Transport/client/stages/lab4/complete
docker build -t gns3-lab/transport-server:lab4-complete \
  images/Transport/server/stages/lab4/complete
```

Run their smoke tests with:

```sh
images/Transport/client/stages/lab4/complete/tests/smoke.sh
images/Transport/server/stages/lab4/complete/tests/smoke.sh
```

Both images keep an interactive Bash default so the GNS3 Start commands from
the Lab 4 design can configure `eth0` and open a console. Start the receiver
from the Server console with `iperf3 -s -p 5201`. BBR availability and the
`fq` qdisc remain properties of the GNS3 Docker host kernel, not of these
images.

The Client image includes the Lab 4 observation script at
`/opt/cc-lab/run_cc_client.sh`, with executable permissions. After starting
the Server and packet capture, run it in the Client console:

```sh
cd /opt/cc-lab
./run_cc_client.sh cubic run01
# For a separate BBR run, with packet loss reset to 0%:
./run_cc_client.sh bbr run01
```

Each run lasts 90 seconds, samples `ss` every 0.2 seconds, and prompts the
operator to set GNS3 packet loss to 2% at 30 seconds and back to 0% at 50
seconds. The script writes iperf3 JSON, `ss` logs, and event timestamps into
the current directory and refuses to overwrite an existing run. Export the
results before deleting or recreating the node; only the script is included
in the image. BBR must already be available in the host kernel.
