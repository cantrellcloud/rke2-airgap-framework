
SHELL := /bin/bash

.PHONY: template offline server agent verify

template:
	sudo scripts/rke2-node.sh template

offline:
	sudo scripts/rke2-node.sh offline

server:
	sudo scripts/rke2-node.sh server

agent:
	csudo scripts/rke2-node.sh agent

verify:
	sudo scripts/rke2-node.sh verify
