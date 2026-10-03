#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# PLATFORM=evm runs the same Fabric network as PLATFORM=fabric3 (see fabric3.mk, which this
# mirrors) alongside a standalone anvil chain, so the swap sample's owner nodes can hold a wallet
# on each and trade across them via HTLC. See conf-evm/issuer/core.yaml.tmpl and
# scripts/setup_evm.sh for how the EVM leg itself comes up.

# exported vars
FABRIC_SAMPLES := $(abspath fabric-samples)
export FABRIC_SAMPLES

CONF_ROOT=conf-evm
export CONF_ROOT

# Makefile vars
CONTAINER_CLI ?= docker

# Install the utilities needed to run the components on the targeted remote hosts (e.g. make install-prerequisites).
.PHONY: install-prerequisites-fabric
install-prerequisites-fabric:

# Build all the artifacts, the binaries and transfer them to the remote hosts (e.g. make setup).
.PHONY: setup-fabric
setup-fabric:

# Build the config artifacts
.PHONY: build-fabric
build-fabric:

# Clean all the artifacts (configs and bins) built on the controller node (e.g. make clean).
.PHONY: clean-fabric
clean-fabric:
	@for d in "$(CONF_ROOT)"/*/ ; do \
		rm -rf "$$d/keys/fabric" "$$d/keys/evm" "$$d/data" "$$d/core.yaml"; \
	done
	rm -rf "$(CONF_ROOT)/evm"

# Start the targeted hosts (e.g. make fabric-fabric start). Brings up the same Fabric network as
# PLATFORM=fabric3, then deploys the EVM leg against it (anvil, the token contracts, and every
# node's rendered core.yaml) before start-app starts the owner/issuer/endorser containers.
.PHONY: start-fabric
start-fabric:
	@if $(CONTAINER_CLI) network inspect fabric_test >/dev/null 2>&1; then \
		echo "Error: existing fabric_test network detected. Run 'make teardown' first."; \
		exit 1; \
	fi
	"$(FABRIC_SAMPLES)/test-network/network.sh" up createChannel -i 3.1.1
	INIT_REQUIRED="--init-required" "$(FABRIC_SAMPLES)/test-network/network.sh" deployCCAAS  -ccn token_namespace -ccp "$(abspath $$CONF_ROOT)/namespace" -cci "init"
	./scripts/cp_fabric3.sh
	./scripts/setup_evm.sh "$(CONF_ROOT)"

# Stop the targeted hosts (e.g. make fabric-x stop).
.PHONY: stop-fabric
stop-fabric: teardown-fabric

# Teardown the targeted hosts (e.g. make fabric-x teardown).
.PHONY: teardown-fabric
teardown-fabric:
	@"$(FABRIC_SAMPLES)/test-network/network.sh" down
	@$(CONTAINER_CLI) rm -f peer0org1_token_namespace_ccaas peer0org2_token_namespace_ccaas
	@if [ -f "$(CONF_ROOT)/evm/anvil.pid" ]; then \
		kill "$$(cat "$(CONF_ROOT)/evm/anvil.pid")" 2>/dev/null || true; \
	fi
	@for d in "$(CONF_ROOT)"/*/ ; do \
		rm -rf "$$d/keys/fabric" "$$d/keys/evm" "$$d/data" "$$d/core.yaml"; \
	done
	rm -rf "$(CONF_ROOT)/evm"
	@$(CONTAINER_CLI) network inspect fabric_test >/dev/null 2>&1 && $(CONTAINER_CLI) network rm fabric_test || true

# Restart the targeted hosts (e.g. make fabric-x restart).
.PHONY: restart-fabric
restart-fabric: teardown-fabric start-fabric
