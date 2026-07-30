# Container runtime — override for rootless Podman:
#   make start DOCKER=podman COMPOSE="podman compose"
DOCKER  ?= docker
COMPOSE ?= docker compose

UID := $(shell id -u)
GID := $(shell id -g)
export UID
export GID
export DOCKER
export COMPOSE

# ─── Setup ───────────────────────────────────────────────────────────────────

.PHONY: init
init:
	@$(MAKE) -C ../devnet init

blockscout.env:
	@echo "Generating $@..."
	@printf 'POSTGRES_PASSWORD=%s\nSECRET_KEY_BASE=%s\n' \
		"$$(openssl rand -hex 32)" \
		"$$(openssl rand -hex 64)" > blockscout.env

# ─── Start ───────────────────────────────────────────────────────────────────

.PHONY: start-node
start-node:
	@$(MAKE) -C ../devnet start
	@$(MAKE) -C ../devnet init-namespace NS=basic POLICY="OR('Org1MSP.member')"
	@mkdir -p ./data/gateway
	@$(COMPOSE) -f compose.gateway.yaml up -d
	@echo "Waiting for gateway to be healthy..."
	@until [ "$$($(DOCKER) inspect -f '{{.State.Health.Status}}' gateway 2>/dev/null)" != "starting" ]; do sleep 1; done
	@[ "$$($(DOCKER) inspect -f '{{.State.Health.Status}}' gateway 2>/dev/null)" = "healthy" ] || (echo "Error: gateway is unhealthy — check: docker logs gateway"; exit 1)
	@echo "EVM RPC ready at http://localhost:8545"

.PHONY: start
start: blockscout.env start-node
	@$(COMPOSE) -f compose.blockscout.yaml --env-file blockscout.env up -d
	@echo "Visit the block explorer at http://localhost:8000/ (might take a minute to load)"

# ─── Stop / Purge ─────────────────────────────────────────────────────────────

# Start the Fabric-level block explorer (optional, complements Blockscout).
# Shows raw Fabric blocks and transactions at http://localhost:3000.
# Requires a running stack (make start-node or make start).
.PHONY: start-explorer
start-explorer:
	@$(MAKE) -C ../devnet start-explorer

.PHONY: stop
stop:
	@$(COMPOSE) -f compose.blockscout.yaml down 2>/dev/null || true
	@$(COMPOSE) -f compose.gateway.yaml down 2>/dev/null || true
	@$(MAKE) -C ../devnet stop

.PHONY: purge
purge:
	@$(COMPOSE) -f compose.blockscout.yaml down 2>/dev/null || true
	@$(COMPOSE) -f compose.gateway.yaml down 2>/dev/null || true
	@$(MAKE) -C ../devnet purge
	@rm -rf data/
	@rm -rf .token-address

# ─── Build (optional) ─────────────────────────────────────────────────────────

# Recompile src/Token.sol and refresh the committed erc20.bin / erc20.abi.
# Only needed if you change the contract — the demo ships a prebuilt artifact.
# Requires Foundry (forge).
.PHONY: build
build:
	@forge soldeer install
	@forge build
	@forge inspect src/Token.sol:Token bytecode | sed 's/^0x//' | tr -d '\n' > erc20.bin
	@forge inspect src/Token.sol:Token abi --json > erc20.abi
	@echo "Regenerated erc20.bin and erc20.abi from src/Token.sol"

# ─── Demo ─────────────────────────────────────────────────────────────────────

ADMIN_KEY      := 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
EXPLORER       ?= http://localhost:8000
NAME           ?= My Token
SYMBOL         ?= TKN
SUPPLY         ?= 1000000
AMOUNT         ?= 100

.PHONY: deploy
deploy:
	@CONTRACT=$$(cast send --rpc-url fabricx --private-key $(ADMIN_KEY) \
	  --create "$$(cat erc20.bin)" \
	  'constructor(string,string,uint256)' '$(NAME)' '$(SYMBOL)' '$(SUPPLY)000000000000000000' \
	  | awk '/contractAddress/ {print $$2}') && \
	  echo $$CONTRACT > .token-address && \
	  printf '\nDeployed %s (%s): %s/address/%s\n\n' "$(NAME)" "$(SYMBOL)" "$(EXPLORER)" "$$CONTRACT"

CONTRACT ?= $(shell cat .token-address 2>/dev/null)

.PHONY: transfer
transfer:
	@test -n "$(TO)" || (echo "Usage: make transfer TO=0x... [AMOUNT=100] [CONTRACT=0x...]"; exit 1)
	@test -n "$(CONTRACT)" || (echo "No contract address. Run 'make deploy' first or pass CONTRACT=0x..."; exit 1)
	@TX=$$(cast send --rpc-url fabricx --private-key $(ADMIN_KEY) \
	    $(CONTRACT) "transfer(address,uint256)" \
	    $(TO) '$(AMOUNT)000000000000000000' \
	    | awk '/^transactionHash/ {print $$2}') && \
	  printf '\nTransferred %s tokens to %s: %s/tx/%s\n\n' "$(AMOUNT)" "$(TO)" "$(EXPLORER)" "$$TX"

# Verify the deployed source on the explorer, unlocking the Read/Write Contract
# tabs. Pass the same NAME/SYMBOL/SUPPLY you deployed with (constructor args must
# match). Requires Foundry; compiler settings come from foundry.toml.
.PHONY: verify
verify:
	@test -n "$(CONTRACT)" || (echo "No contract address. Run 'make deploy' first or pass CONTRACT=0x..."; exit 1)
	@forge soldeer install >/dev/null 2>&1
	@forge verify-contract $(CONTRACT) src/Token.sol:Token \
	    --verifier blockscout --verifier-url 'http://localhost:8000/api/' \
	    --constructor-args $$(cast abi-encode 'constructor(string,string,uint256)' '$(NAME)' '$(SYMBOL)' '$(SUPPLY)000000000000000000') \
	    --watch && \
	  printf '\nVerified: %s/address/%s?tab=contract\n\n' "$(EXPLORER)" "$(CONTRACT)"
