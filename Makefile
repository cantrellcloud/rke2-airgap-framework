
SHELL := /bin/bash

.PHONY: template offline server agent verify

template:
	cd scripts && sudo ./rke2-node.sh template

offline:
	cd scripts && sudo ./rke2-node.sh offline

server:
	cd scripts && sudo ./rke2-node.sh server

agent:
	cd scripts && sudo ./rke2-node.sh agent

verify:
	cd scripts && sudo ./rke2-node.sh verify
