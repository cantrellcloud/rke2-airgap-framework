
SHELL := /bin/bash

.PHONY: template offline server agent verify

template:
	sudo bash scripts/rke2-node.sh template

offline:
	sudo bash scripts/rke2-node.sh offline

server:
	sudo bash scripts/rke2-node.sh server

agent:
	csudo bash scripts/rke2-node.sh agent

verify:
	sudo bash scripts/rke2-node.sh verify
