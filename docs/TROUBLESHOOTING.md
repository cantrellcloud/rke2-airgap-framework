
# Troubleshooting

## Registry auth/CA

- Verify reachability and auth:
  ```bash
  curl -u admin:'ZAQwsx!@#123' -I https://kuberegistry.dev.kube/v2/ --cacert /path/to/kuberegistry-ca.crt
  ```
- Ensure `/etc/rancher/rke2/registries.yaml` contains the correct mirrors and `configs` block with username/password.
- If you rotate credentials, restart `rke2-server`/`rke2-agent` after updating `registries.yaml`.

## Pre-warm not happening

- Confirm your list is present:
  ```bash
  ls -l /var/lib/rancher/rke2/agent/images/01-images.txt
  ```
- Check service is running:
  ```bash
  systemctl status rke2-server  # or rke2-agent
  journalctl -u rke2-server -f
  ```

## Image still pulling from the internet

- Add a mirror stanza for the upstream registry that image uses (e.g., `quay.io`, `ghcr.io`) in `registries.yaml`.
- Confirm `system-default-registry: kuberegistry.dev.kube/rke2` is in `/etc/rancher/rke2/config.yaml`.
- Restart the RKE2 service.

## Installer cannot be reached

- Use `--offline-installer` and provide a local `get.rke2.sh` if your environment is fully air-gapped.
- Mirror the RKE2 artifacts internally and serve the script from an internal URL, then call `--install-url` with that URL.
