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

DOCKER          ?= docker
COMPOSE         ?= docker compose
RUN_AS          ?= --user "$(UID):$(GID)"
COMPOSE_OVERRIDE ?=

# Namespace init defaults — override on the command line or per-target below
NS      ?= mynamespace
POLICY  ?= AND('Org1MSP.member','Org2MSP.member')
NETWORK ?= fabric-x

# ─── Init ───────────────────────────────────────────────────────────────────

.PHONY: init
init:
	@rm -rf $(FABRICX_DIR)/crypto
	@# Routers and assemblers accept client certs from any peer org — concatenate all peer TLS CAs.
	@$(DOCKER) run --rm \
		$(RUN_AS) \
		-v "$(FABRICX_DIR):/config" \
		$(TOOLS_IMAGE) \
		sh -c 'cryptogen generate --config=/config/crypto-config.yaml --output=/config/crypto \
			&& cat /config/crypto/peerOrganizations/org1.example.com/msp/tlscacerts/tlsca.org1.example.com-cert.pem \
			       /config/crypto/peerOrganizations/org2.example.com/msp/tlscacerts/tlsca.org2.example.com-cert.pem \
			       > /config/crypto/client-tls-ca.pem'
	@$(DOCKER) run --rm \
		$(RUN_AS) \
		-v "$(FABRICX_DIR):/config" \
		-v "$(FABRICX_DIR)/crypto:/crypto" \
		--entrypoint /usr/local/bin/armageddon \
		$(ORDERER_IMAGE) \
		createSharedConfigProto \
		--sharedConfigYaml=/config/shared_config.yaml \
		--output=/config/crypto/
	@$(DOCKER) run --rm \
		$(RUN_AS) \
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
	@if [ ! -d "$(FABRICX_DIR)/crypto" ]; then echo "Error: crypto directory not found — run 'make init' first."; exit 1; fi
	@if nc -z localhost 7050 2>/dev/null; then echo "Error: port 7050 is already in use — stop any running Fabric orderer before starting."; exit 1; fi
	@for p in 1 2 3 4; do mkdir -p \
		$(FABRICX_DIR)/data/orderers/party$$p-router \
		$(FABRICX_DIR)/data/orderers/party$$p-batcher \
		$(FABRICX_DIR)/data/orderers/party$$p-consenter \
		$(FABRICX_DIR)/data/orderers/party$$p-assembler; done
	@mkdir -p $(FABRICX_DIR)/data/committer-org1/sidecar-ledger \
		$(FABRICX_DIR)/data/committer-org1/db
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml $(COMPOSE_OVERRIDE) up -d
	@echo "Waiting for orderer to be ready..."
	@while ! nc -z localhost 7050 2>/dev/null; do sleep 1; done
	@echo "Waiting for committer to be ready..."
	@while ! nc -z localhost 7001 2>/dev/null; do sleep 1; done

.PHONY: stop
stop:
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml $(COMPOSE_OVERRIDE) -f $(FABRICX_DIR)/compose.org2.yaml down

.PHONY: purge
purge:
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml $(COMPOSE_OVERRIDE) -f $(FABRICX_DIR)/compose.org2.yaml down
	@# Postgres (UID 70 on Alpine) creates files the host user can't delete on Linux; use a root container.
	@$(DOCKER) run --rm -v "$(FABRICX_DIR)/data:/data" alpine rm -rf \
		/data/committer-org1/db /data/committer-org2/db 2>/dev/null || true
	@rm -rf $(FABRICX_DIR)/data

# ─── Both orgs (Org1 + Org2 committer stacks) ───────────────────────────────

.PHONY: start-both
start-both:
	@if [ ! -d "$(FABRICX_DIR)/crypto" ]; then echo "Error: crypto directory not found — run 'make init' first."; exit 1; fi
	@if nc -z localhost 7050 2>/dev/null; then echo "Error: port 7050 is already in use — stop any running Fabric orderer before starting."; exit 1; fi
	@for p in 1 2 3 4; do mkdir -p \
		$(FABRICX_DIR)/data/orderers/party$$p-router \
		$(FABRICX_DIR)/data/orderers/party$$p-batcher \
		$(FABRICX_DIR)/data/orderers/party$$p-consenter \
		$(FABRICX_DIR)/data/orderers/party$$p-assembler; done
	@mkdir -p $(FABRICX_DIR)/data/committer-org1/sidecar-ledger \
		$(FABRICX_DIR)/data/committer-org1/db \
		$(FABRICX_DIR)/data/committer-org2/sidecar-ledger \
		$(FABRICX_DIR)/data/committer-org2/db
	@$(COMPOSE) -f $(FABRICX_DIR)/compose.yaml $(COMPOSE_OVERRIDE) -f $(FABRICX_DIR)/compose.org2.yaml up -d
	@echo "Waiting for orderer to be ready..."
	@while ! nc -z localhost 7050 2>/dev/null; do sleep 1; done
	@echo "Waiting for committers to be ready..."
	@while ! nc -z localhost 7001 2>/dev/null; do sleep 1; done
	@while ! nc -z localhost 7002 2>/dev/null; do sleep 1; done

# ─── Dev mode (all-in-one test committer, includes built-in orderer) ─────────

.PHONY: start-dev
start-dev:
	@if [ ! -d "$(FABRICX_DIR)/crypto" ]; then echo "Error: crypto directory not found — run 'make init' first."; exit 1; fi
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
		$(RUN_AS) \
		--env "FX_NS=$(NS)" \
		--env "FX_POLICY=$(POLICY)" \
		-v "$(FABRICX_DIR)/fxconfig.yaml:/config/fxconfig.yaml:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/peers/fxconfig.org1.example.com/tls:/tls:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp:/msp:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/msp/tlscacerts/tlsca.org1.example.com-cert.pem:/org-tls-ca.pem:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/ordererOrganizations/orderer-org-1/msp/tlscacerts/tlsca.orderer-org-1-cert.pem:/orderer-tls-ca.pem:ro,Z" \
		$(TOOLS_IMAGE) \
		sh -c 'fxconfig namespace list --config=/config/fxconfig.yaml 2>/dev/null | grep -q ") $$FX_NS:" || \
		fxconfig namespace create "$$FX_NS" --policy="$$FX_POLICY" --endorse --submit --wait --config=/config/fxconfig.yaml'
endef

.PHONY: list-namespaces
list-namespaces:
	@$(DOCKER) run --rm --network $(NETWORK) \
		$(RUN_AS) \
		-v "$(FABRICX_DIR)/fxconfig.yaml:/config/fxconfig.yaml:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/peers/fxconfig.org1.example.com/tls:/tls:ro,Z" \
		-v "$(FABRICX_DIR)/crypto/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp:/msp:ro,Z" \
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
