
# Quick Start (5–10 minutes)

## 0) Requirements
- Ubuntu 24.04 LTS (Minimized)
- One VM **with internet** (to build the template)
- Private registry at `kuberegistry.dev.kube/rke2` (+ CA + creds)

## 1) Template (online once)
```
make template VERSION=v1.33.4+rke2r1
# Power off and convert to your hypervisor template
```

## 2) Clone into the air-gap — Stage 1
```
make stage1 ROLE=server HOSTNAME=cp-01 IFACE=eno1 IP_CIDR=10.0.4.101/24 GW=10.0.4.1 DNS=10.0.0.10,1.1.1.1
# reboots
```

## 3) Stage 2 — Registry + Pre‑warm + Install + Verify
```
make stage2 IMAGES_LIST=./rke2-mirror/lists/images.all.txt CA_BUNDLE=examples/kuberegistry-ca.crt
```

## 4) Verify and export kubeconfig
```
make verify
make kubeconfig-export
kubectl get nodes
```
