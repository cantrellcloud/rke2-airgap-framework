
# RKE2 Air-Gap Framework (Slim)

Exactly five commands via `make`:

```
make template   # prep online VM as template (cache installer, base OS tune)
make offline    # prompt for hostname/IP; preview; power down (default) or reboot; changes apply on next boot
make server     # finalize as RKE2 server: registry config + install/start rke2-server; auto-runs verify
make agent      # finalize as RKE2 agent: join to server + registry config + install/start; auto-runs verify
make verify     # run post-install verification any time
```

Everything logs to `/var/log/rke2-airgap.log`.

## Notes
- OS: Ubuntu 24.04 LTS (Minimized)
- RKE2: `v1.33.4+rke2r1` (set `RKE2_VERSION` to override before running)
- The installer is cached to `/opt/rke2/get.rke2.sh` during **template** (must be run **online**).
- `offline` backs up and removes any existing netplan files before writing `01-rke2-static.yaml`. The file is not applied until you choose shutdown/reboot at the end.

---

## Appendix A — Troubleshooting

**Template**
- *“Cached installer not found” when running `server`/`agent`*: Re-run `make template` on a connected VM. The installer should live at `/opt/rke2/get.rke2.sh`.
- *Time drift causes TLS errors*: Ensure `chrony` is active (`systemctl status chrony`) and the clock is sane.

**Offline**
- *Picked the wrong NIC/IP*: Just run `make offline` again; it backs up and replaces `/etc/netplan/01-rke2-static.yaml` and previews before committing. Changes apply only after shutdown/reboot.
- *No network after boot*: Confirm the interface name (e.g., `ip -o link`), CIDR format (`10.0.4.101/24`), and gateway reachability.

**Server / Agent**
- *Agent won’t join*: Verify the server URL is `https://<server-ip>:9345`, the token is correct (from `/var/lib/rancher/rke2/server/node-token`), and that the agent can reach the server on TCP/9345.
- *Registry pulls fail*: Check DNS for the registry hostname, CA bundle path (if using a private CA), and credentials in `/etc/rancher/rke2/registries.yaml`.

**Verify**
- *br_netfilter / overlay not loaded*: `modprobe br_netfilter overlay`; then `make verify` again. The template step writes `/etc/modules-load.d/rke2.conf` to persist across boots.
- *Sysctls wrong*: `sysctl --system` should apply `/etc/sysctl.d/99-rke2.conf`.

**Logs**
- All actions log to `/var/log/rke2-airgap.log`.
- RKE2 services log to journald: `journalctl -u rke2-server -f` or `journalctl -u rke2-agent -f`.

---

## Appendix B — FAQ

**Q: What Ubuntu variant is supported?**  
A: Ubuntu 24.04 LTS (Minimized). Others may work but aren’t tested in this slim flow.

**Q: Does this install containerd from apt?**  
A: No. RKE2 ships its own containerd. Less drift, fewer surprises.

**Q: Where are registry creds stored?**  
A: `/etc/rancher/rke2/registries.yaml` (containerd format, plaintext). Limit host access and rotate creds.

**Q: Can I pre-warm images in this slim version?**  
A: Not built-in here. This flow assumes your registry already hosts all required images for your RKE2 version.

**Q: How do I change RKE2 version?**  
A: Export `RKE2_VERSION` before running `make template` (e.g., `RKE2_VERSION=v1.33.4+rke2r1`).

---

## Appendix C — One-screen flow (Mermaid)

```mermaid
flowchart TD
  T[template (online)] --> O[offline (air-gap)]
  O -->|preview OK| P{Power action}
  P -->|Shutdown (default)| S[power off]
  P -->|Reboot| R[reboot]
  S --> SV[server]
  R --> SV
  SV[server] --> V[verify]
  SV --> A[agent]
  A --> V
```

---

## Appendix D — Prompt examples

**Offline**
```
New hostname: cp-01
Primary interface (e.g., eno1): eno1
IPv4/CIDR (e.g., 10.0.4.101/24): 10.0.4.101/24
Gateway (e.g., 10.0.4.1): 10.0.4.1
DNS (comma-separated, e.g., 10.0.0.10,1.1.1.1): 10.0.0.10,1.1.1.1

Are these settings correct? [Y/n]:
Selection [1/2]: 1   # 1 = Shutdown (default), 2 = Reboot
```

**Server**
```
Private registry prefix (e.g., kuberegistry.dev.kube/rke2): kuberegistry.dev.kube/rke2
Registry username: admin
Registry password: ********
Path to registry CA bundle (PEM) [optional]: /root/kuberegistry-ca.crt
```

**Agent**
```
RKE2 server URL (e.g., https://10.0.4.101:9345): https://10.0.4.101:9345
Join token (or path to token file): /tmp/node-token
Private registry prefix (e.g., kuberegistry.dev.kube/rke2): kuberegistry.dev.kube/rke2
Registry username: admin
Registry password: ********
Path to registry CA bundle (PEM) [optional]: /root/kuberegistry-ca.crt
```
