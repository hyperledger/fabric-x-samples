# Endorser – Example Fabric-X Service

This example shows how to build a custom endorser service using the
[fabric-x-sdk](https://github.com/hyperledger/fabric-x-sdk/). An endorser is like chaincode in
classic Fabric: it receives transaction proposals, reads and writes world state through a
`SimulationStore`, and returns signed read/write sets. Unlike chaincode, it runs as a standalone
gRPC service — outside the peer, in your own process.

You will build and run two endorser instances, submit transactions through the included client CLI,
and see how to wire in your own `Executor` — the single interface you implement to add application
logic.

## Prerequisites

- Go 1.26+
- Docker (for the test network committer and orderer)

## Quick Start

### 1. Generate crypto material and start the test network

```shell
make init    # generate TLS certs and MSP material (only once)
make start # start committer + orderer in Docker
```

### 2. Build

```shell
make build   # compiles bin/endorser and bin/client
```

### 3. Start the endorsers

Run each in a **separate terminal** — logs stream to stdout so you can see what's happening:

**Terminal 1**
```shell
./bin/endorser -c sampleconfig/endorser1.yaml
```

**Terminal 2**
```shell
./bin/endorser -c sampleconfig/endorser2.yaml
```

Each endorser logs `starting endorser` and then listens for proposals (endorser1 on `:9001`,
endorser2 on `:9002`).

### 4. Send a transaction

```shell
# write a value
./bin/client -c sampleconfig/client.yaml invoke '{"Args":["set", "greeting", "hello world"]}'

# read it back
./bin/client -c sampleconfig/client.yaml query '{"Args":["get", "greeting"]}'
```

`invoke` collects endorsements from both endorsers and submits to the orderer.  
`query` collects endorsements and prints the response payload — it does not submit.

The transaction argument follows the Fabric peer CLI convention: a JSON `Args` array with the
function name as the first element, or a `{"function": "...", "Args": [...]}` object.

### 5. Tear down

Stop the running endorsers. Then stop the test container.

```shell
make stop  # stop the Docker test network
```

## Writing Your Own Executor

The `Executor` interface is the only thing you need to implement to add your own logic:

```go
type Executor interface {
    Execute(ctx context.Context, newStore StoreFactory, inv endorsement.Invocation) (endorsement.ExecutionResult, error)
}
```

The included [`SampleExecutor`](./cmd/endorser/executor.go) is a simple key/value getter and setter
— about 40 lines. It reads from and writes to the `SimulationStore`, which captures the read/write
set that the endorser will sign.

To plug in your own executor, edit [`cmd/endorser/main.go`](./cmd/endorser/main.go) and add it to
the `executors` map:

```go
executors := map[string]service.Executor{
    "my-namespace": MyExecutor{},
}
```

Each key is a namespace. The namespace must be registered in the network configuration via
`fxconfig` (see `testdata/fxconfig-docker.yaml` for the namespace used by this sample).

If the `SimulationStore` does not give you enough control, you can call `store.Result()` early and
modify the resulting read/write set directly before returning `endorsement.Success(...)`.

## Project Structure

```
├── cmd/
│   ├── endorser/        # Endorser service entry point + SampleExecutor
│   └── client/          # Developer client CLI
├── config/              # Configuration structures
├── sampleconfig/        # Sample config files (endorser1/2, client)
├── service/             # Service implementation and integration tests
├── testdata/            # Network config, crypto-config, and generated crypto material
├── compose.yml          # Docker Compose for committer + orderer
├── Makefile
├── go.mod
└── README.md
```

## Configuration

### Files

See the `sampleconfig/` folder for endorser and client configs, and `testdata/` for the network
and crypto material used by the test environment.

### TLS Modes

| Mode   | Description                                            |
| ------ | ------------------------------------------------------ |
| `none` | No TLS — for local development without crypto material |
| `tls`  | One-sided TLS — server certificate only                |
| `mtls` | Mutual TLS — both sides present certificates           |

### Environment Variables

Any config field can be overridden with the `ENDORSER_` prefix:

```shell
ENDORSER_SERVER_ENDPOINT_PORT=8080 ./bin/endorser -c sampleconfig/endorser1.yaml
```

## Core Dependencies

- [`fabric-x-sdk`](https://github.com/hyperledger/fabric-x-sdk) — endorsement building, block
  delivery, identity, versioned state
- [`fabric-x-committer`](https://github.com/hyperledger/fabric-x-committer) — `utils/connection`
  for gRPC server setup
- [`fabric-x-common`](https://github.com/hyperledger/fabric-x-common) — config parsing
