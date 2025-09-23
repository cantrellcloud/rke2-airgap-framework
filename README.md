
# RKE2 Air‑Gap Framework

Turnkey framework to mirror RKE2 images and bootstrap an **air‑gapped** RKE2 cluster on **Ubuntu 24.04 (Minimized)**.

- Private registry root (mirrors): **kuberegistry.dev.kube/rke2**
- Auth: **admin / ZAQwsx!@#123** (example defaults; override in `.env`)
- RKE2: **v1.33.4+rke2r1** (linux-amd64)
- Logs: `/var/log/rke2-ubuntu-node.log`

## Design & how the framework works

- **Template mode (online once)** caches the official RKE2 installer to `/opt/rke2/get.rke2.sh` and primes Ubuntu 24.04 (modules/sysctls/swap).
- **Stage 1 (offline)** gathers role + static IP/DNS/GW (flags or prompts), writes netplan, applies OS tuning, reboots.
- **Stage 2 (offline)** writes `registries.yaml` (mirrors+auth+CA), drops image pre‑warm list, installs RKE2 from cache, starts `rke2-{server|agent}`, runs verification.
- **Image mirroring** is handled by `pull-all.sh` (internet) and `push-all.sh` (air-gap), with `verify-mirror.sh` and `mirror-compare.sh` to assert presence.
- **Addons** (MetalLB + Contour) are shipped retagged to your registry. `make addons` can render the IP pool from `METALLB_POOL` and apply; `make whoami` deploys a test app and prints a `curl` line.
- **Ops**: `make verify`, `make doctor`, and a systemd timer for daily self-checks.

The framework is idempotent where possible: stage markers prevent accidental re‑runs; configuration is written to dedicated files and logs tracked in `/var/log/rke2-ubuntu-node.log`.

## Flow (at a glance)

```mermaid
flowchart TD
  A[Start] --> B{--template flag?}
  B -- Yes --> C[Set hostname=rke2image]
  C --> D[Install base packages, kernel mods, sysctls, swapoff]
  D --> E[Cache installer → /opt/rke2/get.rke2.sh]
  E --> F[Power off & convert to template]
  B -- No --> G{Stage markers?}
  G -- None --> H[Stage 1: role/hostname/IP]
  H --> I[Write netplan & hostname]
  I --> J[Prep base OS]
  J --> K[Reboot]
  G -- Stage 1 only --> L[Stage 2: registry (mirrors+auth+CA)]
  L --> M[Pre-warm list (optional)]
  M --> N[Probe https://REGISTRY_HOST/v2/]
  N --> O[Install RKE2 from cache]
  O --> P[Start rke2-{server|agent}]
  P --> Q{--skip-verify?}
  Q -- No --> R[Verify modules/sysctls/swap/registry/service]
  Q -- Yes --> S[Skip verify]
  R --> T[Done]
  S --> T
```

---

## Quick Start

See **[docs/QUICKSTART.md](docs/QUICKSTART.md)** for a 5–10 minute path. For a guided first cluster with MetalLB + Contour and a demo app, see **[docs/FIRST_CLUSTER.md](docs/FIRST_CLUSTER.md)**.

## Script (node prep): `scripts/rke2-ubuntu-node.sh`

- Modes:
  - `--template` (online once) caches the official installer to `/opt/rke2/get.rke2.sh` and sets hostname `rke2image`.
  - **Offline two‑stage** for clones:
    - **Stage 1:** role/hostname/IP → netplan → reboot
    - **Stage 2:** registry (auth + CA), pre‑warm list, *install RKE2 from cache*, start service, verify
- All output is logged to `/var/log/rke2-ubuntu-node.log` (and echoed to console).

### Flags (alphabetical)

```
--allow-leaf-ca
--ca
--dns
--gw
--hostname
--iface
--images
--install-url
--ip-cidr
--pass
--registry
--role
--server-url
--skip-verify
--template
--token
--token-file
--user
--version
```

## Flag reference (what each flag does)

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

### Verify checks
- Registry `/v2/` auth reachability (with CA if provided)
- Kernel modules: `overlay`, `br_netfilter`
- Sysctls: `net.ipv4.ip_forward=1`, `bridge-nf-call-iptables=1`
- Swap disabled
- rke2-{server|agent} service status

---

## Docs

- **Quick Start:** `docs/QUICKSTART.md`
- **First Cluster Walkthrough:** `docs/FIRST_CLUSTER.md`
- **Checklist:** `docs/CHECKLIST.md`
- **Cheat Sheet:** `docs/CHEATSHEET.md`
- **FAQ:** `docs/FAQ.md`
- **One-pager (print):** `docs/SINGLE_PAGE.html`

---

## Makefile (high‑value targets)

```
make help
make template                 # build online template once
make stage1 / stage2          # manual stages
make cluster-server           # one-shot server bootstrap (Stage1→reboot→Stage2)
make cluster-agent            # one-shot agent join (Stage1→reboot→Stage2)
make addons whoami            # install MetalLB+Contour, deploy demo and print curl
make uninstall-addons         # remove demo + addons
make mirror-pull mirror-push  # pull upstream to OCI, push into private registry
make mirror-verify            # every image exists
make mirror-compare           # only missing images
make verify doctor            # node checks
make install-completion       # bash completion
make stage1-tui               # fzf-assisted Stage 1
make kubeconfig-export        # copy kubeconfig to $HOME/.kube/config
make install-doctor           # systemd daily self-check
make build-deb                # build a .deb that installs everything under /opt/rke2-airgap
```

---

## Security & CA notes

- `registries.yaml` stores creds in plaintext (containerd schema). Restrict host access and permissions.
- `--ca` should be the **issuing CA bundle** (intermediates + root). The script enforces `CA:TRUE` unless `--allow-leaf-ca` is set.

---
