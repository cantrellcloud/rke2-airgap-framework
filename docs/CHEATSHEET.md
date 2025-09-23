
# Cheat Sheet

**Template (online once):**
```
make template VERSION=v1.33.4+rke2r1
```

**Server (air-gapped):**
```
make cluster-server HOSTNAME=cp-01 IFACE=eno1 IP_CIDR=10.0.4.101/24 GW=10.0.4.1 DNS=10.0.0.10,1.1.1.1
sudo cat /var/lib/rancher/rke2/server/node-token > /tmp/node-token
make kubeconfig-export
kubectl get nodes
```

**Agent (air-gapped):**
```
make cluster-agent HOSTNAME=w1 IFACE=eno1 IP_CIDR=10.0.4.111/24 GW=10.0.4.1 DNS=10.0.0.10,1.1.1.1   SERVER_URL=https://10.0.4.101:9345 TOKEN_FILE=/tmp/node-token
```

**Addons & demo:**
```
export METALLB_POOL=10.0.4.200-10.0.4.220
export WHOAMI_HOST=demo.dev.kube
make addons
make whoami
```

**Ops:**
```
make verify
make doctor
make install-doctor
```

## Flags (quick reference) (what each flag does)

All flags can be provided as CLI args or via environment variables (see `.env.sample`).  
Flags are **alphabetical** here for quick scanning.

- `--allow-leaf-ca` — Skip CA:TRUE enforcement for `--ca`.
- `--ca <path>` — Issuing CA bundle (PEM). Copied to `/etc/rancher/rke2/kuberegistry-ca.crt`.
- `--dns <ip1,ip2,...>` — DNS servers for netplan.
- `--gw <ip>` — Default gateway for netplan.
- `--hostname <name>` — Hostname during Stage 1.
- `--iface <name>` — Primary NIC (e.g., `eno1`).
- `--images <file>` — Image list to pre‑warm containerd.
- `--install-url <url>` — Source of the RKE2 installer (template mode).
- `--ip-cidr <addr/cidr>` — Static IPv4/CIDR for netplan.
- `--pass <string>` — Registry password for containerd pulls.
- `--registry <host/prefix>` — Registry prefix (e.g., `kuberegistry.dev.kube/rke2`).
- `--role <server|agent>` — Node role.
- `--server-url <https://ip:9345>` — RKE2 server for agents to join.
- `--skip-verify` — Skip post‑install checks.
- `--template` — Online template prep mode.
- `--token <string>` — Cluster join token.
- `--token-file <path>` — File containing the join token.
- `--user <string>` — Registry username.
- `--version <rke2-version>` — RKE2 version for the cached installer.

## Design & how the framework works

- **Template mode (online once)** caches the official RKE2 installer to `/opt/rke2/get.rke2.sh` and primes Ubuntu 24.04 (modules/sysctls/swap).
- **Stage 1 (offline)** gathers role + static IP/DNS/GW (flags or prompts), writes netplan, applies OS tuning, reboots.
- **Stage 2 (offline)** writes `registries.yaml` (mirrors+auth+CA), drops image pre‑warm list, installs RKE2 from cache, starts `rke2-{server|agent}`, runs verification.
- **Image mirroring** is handled by `pull-all.sh` (internet) and `push-all.sh` (air-gap), with `verify-mirror.sh` and `mirror-compare.sh` to assert presence.
- **Addons** (MetalLB + Contour) are shipped retagged to your registry. `make addons` can render the IP pool from `METALLB_POOL` and apply; `make whoami` deploys a test app and prints a `curl` line.
- **Ops**: `make verify`, `make doctor`, and a systemd timer for daily self-checks.

The framework is idempotent where possible: stage markers prevent accidental re‑runs; configuration is written to dedicated files and logs tracked in `/var/log/rke2-ubuntu-node.log`.
