# Resolve this Makefile's own directory so paths work when called via make -C devnet.
FABRICX_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Container images
TOOLS_IMAGE          ?= ghcr.io/hyperledger/fabric-x-tools:1.0.0
ORDERER_IMAGE        ?= ghcr.io/hyperledger/fabric-x-orderer:1.0.0
TEST_COMMITTER_IMAGE ?= docker.io/hyperledger/fabric-x-committer-test-node:1.0.0

UID := $(shell id -u)
GID := $(shell id -g)
export UID
export GID

# Container runtime — override for rootless Podman:
#   make start DOCKER=podman COMPOSE="podman compose"
DOCKER  ?= docker
COMPOSE ?= docker compose

# Namespace init defaults — override on the command line or per-target below
NS      ?= mynamespace
POLICY  ?= AND('Org1MSP.member','Org2MSP.member')
NETWORK ?= fabric-x

# ─── Init ───────────────────────────────────────────────────────────────────

.PHONY: init
init:
	@rm -rf $(FABRICX_DIR)/crypto
	@$(DOCKER) run --rm \
		--user "$(UID):$(GID)" \
		-v "$(FABRICX_DIR):/config" \
		$(TOOLS_IMAGE) \
		cryptogen generate --config=/config/crypto-config.yaml --output=/config/crypto
	@# Routers and assemblers accept client certs from any peer org — concatenate all peer TLS CAs.
	@cat $(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/msp/tlscacerts/tlsca.org1.example.com-cert.pem \
		$(FABRICX_DIR)/crypto/peerOrganizations/org2.example.com/msp/tlscacerts/tlsca.org2.example.com-cert.pem \
		> $(FABRICX_DIR)/crypto/client-tls-ca.pem
	@$(DOCKER) run --rm \
		--user "$(UID):$(GID)" \
		-v "$(FABRICX_DIR):/config" \
		-v "$(FABRICX_DIR)/crypto:/crypto" \
		--entrypoint /usr/local/bin/armageddon \
		$(ORDERER_IMAGE) \
		createSharedConfigProto \
		--sharedConfigYaml=/config/shared_config.yaml \
		--output=/config/crypto/
	@$(DOCKER) run --rm \
		--user "$(UID):$(GID)" \
		-v "$(FABRICX_DIR):/config" \
		$(TOOLS_IMAGE) \
		configtxgen --channelID mychannel --profile OrgsChannel \
		--outputBlock /config/crypto/config-block.pb.bin \
		--configPath /config

.PHONY: clean
clean:
	@rm -rf $(FABRICX_DIR)/crypto

# ─── Full stack (4-party orderer + Org1 committer) ──────────────────────────

.PHONY: start
start:
	@if nc -z localhost 7050 2>/dev/null; then echo "Error: port 7050 is already in use — stop any running Fabric orderer before starting."; exit 1; fi
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml up -d
	@echo "Waiting for orderer to be ready..."
	@while ! nc -z localhost 7050 2>/dev/null; do sleep 1; done
	@echo "Waiting for committer to be ready..."
	@while ! nc -z localhost 7001 2>/dev/null; do sleep 1; done

.PHONY: stop
stop:
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml -f $(FABRICX_DIR)/compose.org2.yaml down

.PHONY: purge
purge:
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml -f $(FABRICX_DIR)/compose.org2.yaml down
	@if [ "$(DOCKER)" = "podman" ]; then \
		podman unshare rm -rf $(FABRICX_DIR)/data; \
	else \
		rm -rf $(FABRICX_DIR)/data; \
	fi

# ─── Both orgs (Org1 + Org2 committer stacks) ───────────────────────────────

.PHONY: start-both
start-both:
	@if nc -z localhost 7050 2>/dev/null; then echo "Error: port 7050 is already in use — stop any running Fabric orderer before starting."; exit 1; fi
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml -f $(FABRICX_DIR)/compose.org2.yaml up -d
	@echo "Waiting for orderer to be ready..."
	@while ! nc -z localhost 7050 2>/dev/null; do sleep 1; done
	@echo "Waiting for committers to be ready..."
	@while ! nc -z localhost 7001 2>/dev/null; do sleep 1; done
	@while ! nc -z localhost 7002 2>/dev/null; do sleep 1; done

# ─── Dev mode (all-in-one test committer, includes built-in orderer) ─────────

.PHONY: start-dev
start-dev:
	@if nc -z localhost 7050 2>/dev/null; then echo "Error: port 7050 is already in use."; exit 1; fi
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.test-committer.yaml up -d
	@echo "Waiting for test committer to be ready..."
	@while ! nc -z localhost 7001 2>/dev/null; do sleep 1; done

.PHONY: stop-dev
stop-dev:
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.test-committer.yaml down

.PHONY: purge-dev
purge-dev:
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.test-committer.yaml down -v

# ─── Namespace init ─────────────────────────────────────────────────────────
# Run one of these after start or start-dev to create the application namespace.
# Works with both backends: the test-committer exposes the same service aliases
# as the full stack, so applications and fxconfig.yaml need no changes.

define run-fxconfig
	@$(DOCKER) run --rm --network $(NETWORK) \
		--user "$(UID):$(GID)" \
		--env "FX_NS=$(NS)" \
		--env "FX_POLICY=$(POLICY)" \
		-v "$(FABRICX_DIR)/fxconfig.yaml:/config/fxconfig.yaml:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/peers/fxconfig.org1.example.com/tls:/tls:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/users/channel_admin@org1.example.com/msp:/msp:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/msp/tlscacerts/tlsca.org1.example.com-cert.pem:/org-tls-ca.pem:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/ordererOrganizations/orderer-org-1/msp/tlscacerts/tlsca.orderer-org-1-cert.pem:/orderer-tls-ca.pem:ro,Z" \
		$(TOOLS_IMAGE) \
		sh -c 'fxconfig namespace list --config=/config/fxconfig.yaml 2>/dev/null | grep -q ") $$FX_NS:" || \
		fxconfig namespace create "$$FX_NS" --policy="$$FX_POLICY" --endorse --submit --wait --config=/config/fxconfig.yaml'
endef

.PHONY: list-namespaces
list-namespaces:
	@$(DOCKER) run --rm --network $(NETWORK) \
		--user "$(UID):$(GID)" \
		-v "$(FABRICX_DIR)/fxconfig.yaml:/config/fxconfig.yaml:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/peers/fxconfig.org1.example.com/tls:/tls:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/users/channel_admin@org1.example.com/msp:/msp:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/msp/tlscacerts/tlsca.org1.example.com-cert.pem:/org-tls-ca.pem:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/ordererOrganizations/orderer-org-1/msp/tlscacerts/tlsca.orderer-org-1-cert.pem:/orderer-tls-ca.pem:ro,Z" \
		$(TOOLS_IMAGE) \
		fxconfig namespace list --config=/config/fxconfig.yaml

.PHONY: init-namespace-org1
init-namespace-org1: POLICY = AND('Org1MSP.member')
init-namespace-org1:
	$(run-fxconfig)

.PHONY: init-namespace-org2
init-namespace-org2: POLICY = AND('Org2MSP.member')
init-namespace-org2:
	$(run-fxconfig)

.PHONY: init-namespace
init-namespace:
	$(run-fxconfig)
