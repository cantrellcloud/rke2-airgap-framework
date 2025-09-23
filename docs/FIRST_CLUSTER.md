
# First Cluster Walkthrough

## Server (air‑gap)
Stage 1 → reboot → Stage 2:
```
sudo ./scripts/rke2-ubuntu-node.sh --role server --hostname cp-01 --iface eno1   --ip-cidr 10.0.4.101/24 --gw 10.0.4.1 --dns 10.0.0.10,1.1.1.1
# reboot, then:
sudo ./scripts/rke2-ubuntu-node.sh --images ./rke2-mirror/lists/images.all.txt --ca ./examples/kuberegistry-ca.crt
sudo cat /var/lib/rancher/rke2/server/node-token
```

## Agent (air‑gap)
Stage 1 → reboot → Stage 2 with join args:
```
sudo ./scripts/rke2-ubuntu-node.sh --role agent --hostname w1 --iface eno1   --ip-cidr 10.0.4.111/24 --gw 10.0.4.1 --dns 10.0.0.10,1.1.1.1
# reboot, then:
sudo ./scripts/rke2-ubuntu-node.sh --server-url https://10.0.4.101:9345 --token-file /tmp/node-token   --images ./rke2-mirror/lists/images.all.txt --ca ./examples/kuberegistry-ca.crt
```

## MetalLB & Contour (mirrored)
```
kubectl apply -f examples/manifests/metallb-namespace.yaml
kubectl apply -f examples/manifests/metallb-core.yaml
kubectl apply -f examples/manifests/metallb-ipaddresspool.yaml
kubectl apply -f examples/manifests/metallb-l2advertisement.yaml
kubectl apply -f examples/manifests/contour-namespace.yaml
kubectl apply -f examples/manifests/contour.yaml
```

## Demo (whoami)
```
kubectl apply -f examples/manifests/whoami-deploy.yaml
kubectl apply -f examples/manifests/whoami-httpproxy.yaml
kubectl -n projectcontour get svc envoy -w
```
