TOOLS_IMAGE ?= ghcr.io/hyperledger/fabric-x-tools:0.0.15
TOOLS = docker run --rm -v "$(PWD):/workspace" -w /workspace $(TOOLS_IMAGE)

.PHONY: init-network
init-network:
	rm -rf testdata/crypto
	@docker pull $(TOOLS_IMAGE)
	@$(TOOLS) cryptogen generate --config testdata/crypto-config.yaml --output testdata/crypto
	@$(TOOLS) configtxgen -configPath testdata --channelID mychannel --profile OrgsChannel --outputBlock testdata/crypto/sc-genesis-block.proto.bin

.PHONY: clean
clean: stop
	@rm -rf bin testdata/crypto

.PHONY: start-network
start-network:
	@docker compose up -d --wait test-committer
	@docker compose up fxconfig-init

.PHONY: stop-network
stop-network:
	@docker compose down

.PHONY: test
test:
	@go test -short ./...

.PHONY: build
build:
	@go build -o bin/endorser ./cmd/endorser
	@go build -o bin/client ./cmd/client
