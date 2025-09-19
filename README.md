
# RKE2 Air‑Gap Framework

Turn‑key scripts to mirror all required RKE2 images to a private registry and prep Ubuntu 24.04 (Minimized) nodes with authenticated pulls, pre‑warming, and automated RKE2 install.

> Default private registry path: `kuberegistry.dev.kube/rke2`

## Contents

- `scripts/pull-all.sh` — Pulls required images from the internet to local **OCI archives** (no pushes).
- `scripts/push-all.sh` — Pushes those local OCI archives to your private registry at `kuberegistry.dev.kube/rke2/...`.
- `scripts/config-rke2-nodes.sh` — Configures an existing RKE2 node to use the private registry and pre‑warm images.
- `scripts/rke2-ubuntu-node-init.sh` — One‑shot Ubuntu node prep **+** private registry config/auth **+** pre‑warm **+** RKE2 install with network guards.
- `examples/` — Example values and helper files.
- `docs/` — How‑to and troubleshooting tips.

## Quick Start

### 1) Mirror images on a connected host

```bash
cd scripts
chmod +x pull-all.sh push-all.sh

# Pull from upstream into local OCI archives
./pull-all.sh

# Move the 'rke2-mirror/' folder to an offline box that can reach your registry
# Then push to your registry
./push-all.sh
```

> Images end up at: `kuberegistry.dev.kube/rke2/<upstream-registry>/<repo>:<tag>`

### 2) Prep each Ubuntu 24.04 (Minimized) node

```bash
cd scripts
chmod +x rke2-ubuntu-node-init.sh

# Server (control-plane) example:
sudo ./rke2-ubuntu-node-init.sh   --role server   --version v1.33.4+rke2r1   --images ../rke2-mirror/lists/images.all.txt   --ca ../examples/kuberegistry-ca.crt

# Worker example:
sudo ./rke2-ubuntu-node-init.sh   --role agent   --version v1.33.4+rke2r1   --images ../rke2-mirror/lists/images.all.txt   --ca ../examples/kuberegistry-ca.crt
```

### 3) Optional: Configure existing RKE2 nodes

```bash
chmod +x config-rke2-nodes.sh
sudo ./config-rke2-nodes.sh   -l ../rke2-mirror/lists/images.all.txt   -c ../examples/kuberegistry-ca.crt   --role server
```

## Default credentials (edit as needed)

- Registry root: `kuberegistry.dev.kube/rke2`
- Username: `admin`
- Password: `ZAQwsx!@#123`

Change these in environment variables or flags when running the scripts.

## Push to GitHub

```bash
git init
git remote add origin https://github.com/cantrellcloud/rke2-airgap-framework.git
git add .
git commit -m "Initial commit: RKE2 air-gap framework"
git branch -M main
git push -u origin main
```

See `docs/TROUBLESHOOTING.md` for common issues.


---

## MetalLB address pools (examples for your clusters)

These examples use **Layer2** mode IP pools and one L2Advertisement per cluster. Adjust CIDRs/ranges as needed.

**`examples/metallb-address-pools.yaml`**
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public-pool-j64domain
  namespace: metallb-system
spec:
  addresses:
    - 10.0.4.60-10.0.4.69
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2adv-j64domain
  namespace: metallb-system
spec:
  ipAddressPools:
    - public-pool-j64domain
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public-pool-j64manager
  namespace: metallb-system
spec:
  addresses:
    - 10.0.4.50-10.0.4.59
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2adv-j64manager
  namespace: metallb-system
spec:
  ipAddressPools:
    - public-pool-j64manager
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: public-pool-j52domain
  namespace: metallb-system
spec:
  addresses:
    - 10.0.4.80-10.0.4.89
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2adv-j52domain
  namespace: metallb-system
spec:
  ipAddressPools:
    - public-pool-j52domain
```

Apply to the appropriate cluster:
```bash
kubectl --context j64domain     apply -f examples/metallb-address-pools.yaml
kubectl --context j64manager    apply -f examples/metallb-address-pools.yaml
kubectl --context j52domain     apply -f examples/metallb-address-pools.yaml
```

> Tip: If you want a **static IP** for the Envoy LoadBalancer, add the annotation `metallb.universe.tf/loadBalancerIPs: <ip>` on the service, or select a pool with `metallb.universe.tf/address-pool: <pool-name>`.

## Contour HTTPProxy example

Assuming you installed Contour and it created an **Envoy** `Service` of type `LoadBalancer`, MetalLB will assign an IP from your pool. This HTTPProxy publishes a simple app at `http://demo.dev.kube/`.

**`examples/contour-httpproxy-demo.yaml`**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels: { app: whoami }
  template:
    metadata:
      labels: { app: whoami }
    spec:
      containers:
        - name: whoami
          image: docker.io/traefik/whoami:v1.10.2
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: demo
spec:
  selector: { app: whoami }
  ports:
    - name: http
      port: 80
      targetPort: 80
---
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: whoami
  namespace: demo
spec:
  virtualhost:
    fqdn: demo.dev.kube
  routes:
    - services:
        - name: whoami
          port: 80
```

Apply the demo and inspect the Envoy service IP:
```bash
kubectl apply -f examples/contour-httpproxy-demo.yaml
kubectl -n projectcontour get svc envoy -o wide
# You should see an EXTERNAL-IP from your MetalLB pool (e.g., 10.0.4.61)
```

### Selecting a MetalLB pool or static IP for Envoy

Patch the Envoy service to pick a specific pool or IP:

```bash
# Select a specific pool
kubectl -n projectcontour annotate svc envoy   metallb.universe.tf/address-pool=public-pool-j64domain --overwrite

# Or set a static IP
kubectl -n projectcontour annotate svc envoy   metallb.universe.tf/loadBalancerIPs=10.0.4.61 --overwrite
```
