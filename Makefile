# Makefile for RKE2 air-gap framework
-include .env

VERSION       ?= v1.33.4+rke2r1
REGISTRY_ROOT ?= kuberegistry.dev.kube/rke2
REG_USER      ?= admin
REG_PASS      ?= ZAQwsx!@#123
INSTALL_URL   ?= https://get.rke2.io
IMAGES_LIST   ?= ./rke2-mirror/lists/images.all.txt
CA_BUNDLE     ?= examples/kuberegistry-ca.crt

ROLE          ?= server
HOSTNAME      ?= rke2-node
IFACE         ?= eno1
IP_CIDR       ?= 10.0.4.101/24
GW            ?= 10.0.4.1
DNS           ?= 10.0.0.10,1.1.1.1

SERVER_URL    ?= https://10.0.4.101:9345
TOKEN_FILE    ?= /tmp/node-token
METALLB_POOL  ?= 10.0.4.200-10.0.4.220
WHOAMI_HOST   ?= demo.dev.kube

DEST_ROOT     ?= $(REGISTRY_ROOT)
SHELL := /bin/bash

.PHONY: help
help:
	@echo "Targets: template, stage1, stage2, cluster-server, cluster-agent, addons, whoami, uninstall-addons,"
	@echo "         mirror-pull, mirror-push, mirror-verify, mirror-compare, node-config, verify, doctor,"
	@echo "         install-completion, stage1-tui, kubeconfig-export, install-doctor, start-doctor-now, uninstall-doctor, build-deb"

template:
	sudo scripts/rke2-ubuntu-node.sh --template --version $(VERSION) --install-url $(INSTALL_URL)

stage1:
	cd scripts && sudo ./rke2-ubuntu-node.sh --role $(ROLE) --hostname $(HOSTNAME) --iface $(IFACE) --ip-cidr $(IP_CIDR) --gw $(GW) --dns $(DNS)

stage2:
	cd scripts && sudo ./rke2-ubuntu-node.sh --images $(IMAGES_LIST) --ca $(CA_BUNDLE)

cluster-server:
	cd scripts && sudo ./rke2-ubuntu-node.sh --role server --hostname $(HOSTNAME) --iface $(IFACE) --ip-cidr $(IP_CIDR) --gw $(GW) --dns $(DNS)
	cd scripts && sudo ./rke2-ubuntu-node.sh --images $(IMAGES_LIST) --ca $(CA_BUNDLE)

cluster-agent:
	cd scripts && sudo ./rke2-ubuntu-node.sh --role agent --hostname $(HOSTNAME) --iface $(IFACE) --ip-cidr $(IP_CIDR) --gw $(GW) --dns $(DNS)
	cd scripts && sudo ./rke2-ubuntu-node.sh --role agent --server-url $(SERVER_URL) --token-file $(TOKEN_FILE) --images $(IMAGES_LIST) --ca $(CA_BUNDLE)

addons:
	kubectl apply -f examples/manifests/metallb-namespace.yaml
	kubectl apply -f examples/manifests/metallb-core.yaml
	@echo "--> Rendering IPAddressPool from METALLB_POOL=$(METALLB_POOL)"
	@cat > /tmp/metallb-ipaddresspool.rendered.yaml <<EOF\napiVersion: metallb.io/v1beta1\nkind: IPAddressPool\nmetadata:\n  name: default-pool\n  namespace: metallb-system\nspec:\n  addresses:\n  - $(METALLB_POOL)\nEOF
	kubectl apply -f /tmp/metallb-ipaddresspool.rendered.yaml
	kubectl apply -f examples/manifests/metallb-l2advertisement.yaml
	kubectl apply -f examples/manifests/contour-namespace.yaml
	kubectl apply -f examples/manifests/contour.yaml

whoami:
	kubectl apply -f examples/manifests/whoami-deploy.yaml
	kubectl apply -f examples/manifests/whoami-httpproxy.yaml
	@bash -lc 'set -e; ns=projectcontour; svc=envoy; for i in $$(seq 1 60); do ip=$$(kubectl -n $$ns get svc $$svc -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null || true); if [ -n "$$ip" ]; then echo "External IP: $$ip"; echo "  curl -H \\"Host: $(WHOAMI_HOST)\\" http://$$ip/"; exit 0; fi; sleep 2; done; echo "Timed out waiting for envoy external IP."; exit 1'

uninstall-addons:
	kubectl delete -f examples/manifests/whoami-httpproxy.yaml --ignore-not-found
	kubectl delete -f examples/manifests/whoami-deploy.yaml --ignore-not-found
	kubectl delete -f examples/manifests/contour.yaml --ignore-not-found
	kubectl delete -f examples/manifests/contour-namespace.yaml --ignore-not-found
	kubectl delete -f /tmp/metallb-ipaddresspool.rendered.yaml --ignore-not-found || true
	kubectl delete -f examples/manifests/metallb-l2advertisement.yaml --ignore-not-found
	kubectl delete -f examples/manifests/metallb-core.yaml --ignore-not-found
	kubectl delete -f examples/manifests/metallb-namespace.yaml --ignore-not-found

mirror-pull:
	cd scripts && ./pull-all.sh

mirror-push:
	cd scripts && DEST_ROOT=$(DEST_ROOT) ./push-all.sh

mirror-verify:
	cd scripts && ./verify-mirror.sh $(IMAGES_LIST)

mirror-compare:
	cd scripts && ./mirror-compare.sh $(IMAGES_LIST)

node-config:
	cd scripts && sudo ./config-rke2-nodes.sh --role $(ROLE) --user $(REG_USER) --pass '$(REG_PASS)' -r $(REGISTRY_ROOT) -l $(IMAGES_LIST) -c $(CA_BUNDLE)

install-completion:
	sudo install -m 0644 completion/rke2-ubuntu-node.sh /etc/bash_completion.d/rke2-ubuntu-node.sh || true

verify:
	@echo "== Verify node =="
	@bash -c 'set -euo pipefail; if [ -f "$(CA_BUNDLE)" ]; then CA="--cacert $(CA_BUNDLE)"; else CA=""; fi; REG_HOST=$$(echo $(REGISTRY_ROOT) | cut -d/ -f1); curl -u "$(REG_USER):$(REG_PASS)" -fsSIL --max-time 6 --connect-timeout 3 $$CA https://$$REG_HOST/v2/ >/dev/null && echo "✔ Registry /v2/ reachable with auth" || { echo "✖ Registry /v2/ probe failed"; exit 1; }'; \
	lsmod | grep -q br_netfilter && echo "✔ br_netfilter loaded" || { echo "✖ br_netfilter not loaded"; exit 1; }; \
	lsmod | grep -q overlay && echo "✔ overlay loaded" || { echo "✖ overlay not loaded"; exit 1; }; \
	v=$$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0); [ "$$v" = "1" ] && echo "✔ net.ipv4.ip_forward=1" || { echo "✖ ip_forward=$$v"; exit 1; }; \
	v=$$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0); [ "$$v" = "1" ] && echo "✔ bridge-nf-call-iptables=1" || { echo "✖ bridge-nf-call-iptables=$$v"; exit 1; }; \
	n=$$(swapon --show | wc -l); [ "$$n" = "0" ] && echo "✔ swap disabled" || { echo "✖ swap devices active=$$n"; exit 1; }; \
	if systemctl list-unit-files | grep -q "^rke2-server\\.service"; then systemctl is-active --quiet rke2-server && echo "✔ rke2-server active" || echo "ℹ rke2-server not active"; fi; \
	if systemctl list-unit-files | grep -q "^rke2-agent\\.service"; then systemctl is-active --quiet rke2-agent && echo "✔ rke2-agent active" || echo "ℹ rke2-agent not active"; fi

doctor:
	@echo "== doctor =="
	@bash -lc 'set -e; getent ahosts $${REGISTRY_ROOT%%/*}'; \
	bash -lc 'set -e; host=$${REGISTRY_ROOT%%/*}; timeout 5 bash -c "</dev/tcp/$$host/443" && echo "Port 443 reachable" || echo "Port 443 not reachable"'; \
	df -h /; \
	timedatectl 2>/dev/null || true; chronyc tracking 2>/dev/null || true; \
	nproc; free -h; \
	bash -lc 'test -f /var/log/rke2-ubuntu-node.log && tail -n 50 /var/log/rke2-ubuntu-node.log || echo "No log yet"'

stage1-tui:
	cd scripts && ./stage1-tui.sh

kubeconfig-export:
	cd scripts && sudo ./kubeconfig-export.sh

# systemd doctor
install-doctor:
	sudo install -m 0644 systemd/rke2-airgap-doctor.service /etc/systemd/system/rke2-airgap-doctor.service
	sudo install -m 0644 systemd/rke2-airgap-doctor.timer   /etc/systemd/system/rke2-airgap-doctor.timer
	sudo systemctl daemon-reload
	sudo systemctl enable --now rke2-airgap-doctor.timer

start-doctor-now:
	sudo systemctl start rke2-airgap-doctor.service
	sudo journalctl -u rke2-airgap-doctor.service -n 50 --no-pager || true

uninstall-doctor:
	- sudo systemctl disable --now rke2-airgap-doctor.timer
	- sudo systemctl stop rke2-airgap-doctor.service || true
	- sudo rm -f /etc/systemd/system/rke2-airgap-doctor.service /etc/systemd/system/rke2-airgap-doctor.timer
	- sudo systemctl daemon-reload

# packaging
build-deb:
	cd packaging && ./build-deb.sh 1.0.0
