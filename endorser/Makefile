TOOLS_IMAGE ?= hyperledger/fabric-x-tools:0.0.15
TOOLS = docker run --rm -v "$(PWD):/workspace" -w /workspace $(TOOLS_IMAGE)

.PHONY: init
init:
	rm -rf testdata/crypto
	@$(TOOLS) cryptogen generate --config testdata/crypto-config.yaml --output testdata/crypto
	@$(TOOLS) configtxgen -configPath testdata --channelID mychannel --profile OrgsChannel --outputBlock testdata/crypto/sc-genesis-block.proto.bin

.PHONY: clean
clean: stop
	@rm -rf bin testdata/crypto

.PHONY: start
start:
	@docker compose up -d --wait test-committer
	@docker compose up fxconfig-init

.PHONY: stop
stop:
	@docker compose down

.PHONY: build
build:
	@go build -o bin/endorser ./cmd/endorser
	@go build -o bin/client ./cmd/client
