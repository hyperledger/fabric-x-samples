COMMITTER_IMAGE ?= docker.io/hyperledger/fabric-x-committer-test-node:1.0.3

.PHONY: init-network
# The test committer ships its own crypto material (peer-org-0 / peer-org-1),
# genesis block and per-service configs. We extract it so the endorser, client
# and fxconfig use the same identities the committer trusts.
init-network:
	@rm -rf testdata/crypto && mkdir -p testdata/crypto
	@docker pull $(COMMITTER_IMAGE)
	@cid=$$(docker create $(COMMITTER_IMAGE)); \
		docker cp $$cid:/root/artifacts/. testdata/crypto; \
		docker rm $$cid >/dev/null
	@chmod -R a+rX testdata/crypto

.PHONY: clean
clean: stop-network
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
