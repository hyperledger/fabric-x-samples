#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# exported vars
#
# xdev gets its own conf-xdev/ (mirroring fabric3.mk's conf-f3/) rather than sharing conf/ with
# PLATFORM=fabricx: devnet needs TLS enabled, channel "mychannel", and endorser1-endorsing/
# endorser2-endorsing MSP entries that the real Ansible-driven fabricx network neither has nor
# needs (its channel is "arma", TLS is off). Sharing conf/ between the two broke fabricx's CI job
# when xdev's needs were written into it.
CONF_ROOT=conf-xdev
export CONF_ROOT

# devnet (../devnet) is the canonical Fabric-X network, used here unmodified. The full stack
# (real 4-party Arma orderer + Org1 committer), not devnet's single-container dev mode: FSC's
# generic Fabric driver broadcasts through a BFT quorum and refuses anything under 4 orderers
# (platform/fabric/core/generic/ordering/bft.go), which dev mode's lone mock orderer - standing
# in for party 1 alone - can never satisfy. Both modes expose the same service aliases and the
# same fxconfig.yaml, so nothing below needs to change if that's ever revisited.
DEVNET := $(abspath ../devnet)

# xdev's app containers join devnet's own network instead of the fabric_test network the other
# platforms create themselves.
export TOKENS_NETWORK_NAME=fabric-x

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
		rm -rf "$$d/keys/fabric" "$$d/data"; \
	done

# Start fabric-x: devnet's full stack, then the token namespace. A fresh orderer/committer
# fleet can take a beat past devnet's own readiness wait before it's truly ready to broadcast,
# so retry namespace creation a few times rather than trust a single check; devnet's own target
# is idempotent (it lists before it creates), so re-running it is always safe.
.PHONY: start-fabric
start-fabric:
	@$(MAKE) -C $(DEVNET) start
	@for i in 1 2 3 4 5; do \
		$(MAKE) -C $(DEVNET) init-namespace NS=token_namespace POLICY="OR('Org1MSP.member')" && exit 0; \
		echo "Retrying namespace creation ($$i/5)..."; \
		sleep 2; \
	done; \
	echo "Error: failed to create the token namespace after 5 attempts" >&2; exit 1

# Stop the docker containers.
.PHONY: stop-fabric
stop-fabric:
	@$(MAKE) -C $(DEVNET) stop

# Teardown fabric-x
.PHONY: teardown-fabric
teardown-fabric: stop-fabric

# Restart fabric. This deletes the ledger; the app must be cleaned as well.
.PHONY: restart-fabric
restart-fabric: teardown-fabric start-fabric
