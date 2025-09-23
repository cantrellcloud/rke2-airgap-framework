
# FAQ

**Does this install containerd via apt?**  
No. RKE2 ships its own containerd. Avoids version drift.

**What do I pass to `--ca`?**  
Provide the **issuing CA bundle** (intermediates + root), not the leaf cert. Enforced unless `--allow-leaf-ca`.

**'Illegal option -o pipefail' error?**  
Run with bash: `sudo bash ./scripts/rke2-ubuntu-node.sh`.

**Where are registry creds stored?**  
In `/etc/rancher/rke2/registries.yaml`. It’s plaintext per containerd’s format.

**Can I skip verify?**  
Yes: `--skip-verify`. Recommended to keep it on.
