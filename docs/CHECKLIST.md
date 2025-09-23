
# Operator Checklist

- [ ] Internal DNS resolves `kuberegistry.dev.kube` in the air-gap
- [ ] CA bundle PEM (issuer/intermediates/root) has `CA:TRUE`
- [ ] Credentials tested: `curl -u admin:'****' -I https://kuberegistry.dev.kube/v2/ --cacert ca.pem`
- [ ] Template VM built with `make template` and converted in hypervisor
- [ ] `lists/images.all.txt` exists from `pull-all.sh`
- [ ] Archives pushed to `kuberegistry.dev.kube/rke2/...` via `push-all.sh`
- [ ] Node Stage 1 completed (hostname/IP/netplan) and rebooted
- [ ] Node Stage 2 completed; verify clean
- [ ] `journalctl -u rke2-server -f` (or `rke2-agent`) is healthy
