#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# PLATFORM=xevm is to PLATFORM=xdev what PLATFORM=evm is to PLATFORM=fabric3: the same devnet
# Fabric-X network (see fabricx_dev.mk, which this mirrors) alongside a standalone anvil chain, so
# the swap sample's owner nodes can hold a wallet on each and trade Fabric-X tokens for EVM tokens
# via HTLC. The nodes are built with both the fabricx and evm tags (see Dockerfile and
# common/sdk_x_evm.go); conf-xevm/*/core.yaml.tmpl is conf-xdev's configuration plus an evmtms,
# rendered by scripts/setup_evm.sh.

CONF_ROOT=conf-xevm
export CONF_ROOT

DEVNET := $(abspath ../devnet)

# The app containers and anvil join devnet's own network.
export TOKENS_NETWORK_NAME=fabric-x

# Only endorser1 runs on devnet (compose-endorser2.yml is fabric3/evm only), so one EVM
# endorsement is all the nodes can collect.
EVM_THRESHOLD ?= 1
export EVM_THRESHOLD

CONTAINER_CLI ?= docker

# Install the utilities needed to run the components on the targeted remote hosts (e.g. make install-prerequisites).
.PHONY: install-prerequisites-fabric
install-prerequisites-fabric:

# Build all the artifacts, the binaries and transfer them to the remote hosts (e.g. make setup).
.PHONY: setup-fabric
setup-fabric:
	@$(MAKE) -C $(DEVNET) init
	@CRYPTO_DIR=$(DEVNET)/crypto ./scripts/cp_xdev.sh

# Clean all the artifacts (configs and bins) built on the controller node (e.g. make clean).
.PHONY: clean-fabric
clean-fabric:
	@$(MAKE) -C $(DEVNET) purge
	@$(MAKE) -C $(DEVNET) clean
	@for d in "$(CONF_ROOT)"/*/ ; do \
		rm -rf "$$d/keys/fabric" "$$d/keys/evm" "$$d/data" "$$d/core.yaml"; \
	done
	rm -rf "$(CONF_ROOT)/evm"

# Start devnet's full stack and the token namespace (retried, see fabricx_dev.mk), then deploy the
# EVM leg (anvil, the token contracts, and every node's rendered core.yaml) before start-app starts
# the owner/issuer/endorser containers.
.PHONY: start-fabric
start-fabric:
	@$(MAKE) -C $(DEVNET) start
	@for i in 1 2 3 4 5; do \
		$(MAKE) -C $(DEVNET) init-namespace NS=token_namespace POLICY="OR('Org1MSP.member')" && break; \
		if [ $$i -eq 5 ]; then echo "Error: failed to create the token namespace after 5 attempts" >&2; exit 1; fi; \
		echo "Retrying namespace creation ($$i/5)..."; \
		sleep 2; \
	done
	./scripts/setup_evm.sh "$(CONF_ROOT)"

# Stop the docker containers. anvil goes first: it is attached to devnet's network, which devnet
# cannot remove while anything is still connected to it.
.PHONY: stop-fabric
stop-fabric:
	@$(CONTAINER_CLI) rm -f anvil >/dev/null 2>&1 || true
	@$(MAKE) -C $(DEVNET) stop

# Teardown fabric-x and the EVM leg.
.PHONY: teardown-fabric
teardown-fabric: stop-fabric
	@for d in "$(CONF_ROOT)"/*/ ; do \
		rm -rf "$$d/keys/evm" "$$d/core.yaml"; \
	done
	rm -rf "$(CONF_ROOT)/evm"

# Restart fabric. This deletes the ledger; the app must be cleaned as well.
.PHONY: restart-fabric
restart-fabric: teardown-fabric start-fabric
