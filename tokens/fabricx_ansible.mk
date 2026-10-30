#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# Makefile vars
PROJECT_DIR := $(CURDIR)

# Ansible
ANSIBLE_PATH := $(PROJECT_DIR)/ansible
VENV_DIR := ${ANSIBLE_PATH}/.venv
# Python the venv is built with. ansible-core 2.21 supports 3.12-3.14 and crashes at import time
# on 3.15, so prefer a supported interpreter over whatever `python3` happens to be.
PYTHON ?= $(firstword $(foreach p,python3.14 python3.13 python3.12 python3,$(shell command -v $(p) 2>/dev/null)))
# The playbooks' docker modules need the venv's `requests`; without this Ansible auto-discovers
# the system Python instead.
ANSIBLE_PYTHON_INTERPRETER := ${VENV_DIR}/bin/python
PLAYBOOK_PATH := $(ANSIBLE_PATH)/playbooks
TARGET_HOSTS ?= all
ANSIBLE_CONFIG ?= $(ANSIBLE_PATH)/ansible.cfg

# app
CONF_ROOT=conf

# exported vars
export ANSIBLE_CONFIG
export ANSIBLE_PYTHON_INTERPRETER
export PROJECT_DIR
export CONF_ROOT

# Makefile vars
PLAYBOOK_PATH := $(CURDIR)/ansible/playbooks
TARGET_HOSTS ?= all
CONTAINER_CLI ?= docker

# Install the utilities needed to run the components on the targeted remote hosts (e.g. make install-prerequisites).
.PHONY: install-prerequisites-fabric
install-prerequisites-fabric:
	$(PYTHON) -m venv $(VENV_DIR)
	$(VENV_DIR)/bin/python -m pip install --upgrade pip
	$(VENV_DIR)/bin/python -m pip install -r $(ANSIBLE_PATH)/requirements.txt
	ansible-galaxy collection install -r $(ANSIBLE_PATH)/requirements.yml
	ansible-playbook "$(PLAYBOOK_PATH)/01-install-control-node-prerequisites.yaml"
	ansible-playbook hyperledger.fabricx.install_prerequisites --extra-vars '{"target_hosts": "$(TARGET_HOSTS)"}'

# Build all the artifacts, the binaries and transfer them to the remote hosts (e.g. make setup).
.PHONY: setup-fabric
setup-fabric:
	ansible-playbook "$(PLAYBOOK_PATH)/20-setup.yaml" --extra-vars '{"target_hosts": "$(TARGET_HOSTS)"}'
	./scripts/cp_fabricx.sh

# Clean all the artifacts (configs and bins) built on the controller node (e.g. make clean).
.PHONY: clean-fabric
clean-fabric:
	@rm -rf ./out
	@for d in "$(CONF_ROOT)"/*/ ; do \
		rm -rf "$$d/keys/fabric" "$$d/data"; \
	done

# Start fabric-x on the targeted hosts.
.PHONY: start-fabric
start-fabric:
	@$(CONTAINER_CLI) network inspect fabric_test >/dev/null 2>&1 || $(CONTAINER_CLI) network create fabric_test
	ansible-playbook "$(PLAYBOOK_PATH)/60-start.yaml" --extra-vars '{"target_hosts": "$(TARGET_HOSTS)"}'

# Stop the targeted hosts (e.g. make fabric-x stop).
.PHONY: stop-fabric
stop-fabric:
	ansible-playbook "$(PLAYBOOK_PATH)/70-stop.yaml" --extra-vars '{"target_hosts": "$(TARGET_HOSTS)"}'

# Teardown the targeted hosts (e.g. make fabric-x teardown).
.PHONY: teardown-fabric
teardown-fabric:
	ansible-playbook "$(PLAYBOOK_PATH)/80-teardown.yaml" --extra-vars '{"target_hosts": "$(TARGET_HOSTS)"}'

# Restart the targeted hosts (e.g. make fabric-x restart).
.PHONY: restart-fabric
restart-fabric: teardown-fabric start-fabric
