# Fabric-X devnet

A self-contained Fabric-X network for local development and testing.

**Canonical source:**
[`fabric-x-samples/devnet`](https://github.com/hyperledger/fabric-x-samples/tree/main/devnet) —
copy the entire `devnet/` folder into your project to customize.

For a (distributed) production deployment, please refer to [fabric-x-ansible-collection](https://github.com/LF-Decentralized-Trust-labs/fabric-x-ansible-collection).

## What's included

| Component       | Count       | Description                                                          |
| --------------- | ----------- | -------------------------------------------------------------------- |
| Orderer parties | 4 × 4 = 16  | Arma BFT consensus (Router, Batcher, Consenter, Assembler per party) |
| Committer stack | 6 per org   | Verifier, Validator, Coordinator, Sidecar, Query Service, PostgreSQL |
| Organizations   | Org1 + Org2 | Both orgs are in the genesis block; Org2 committer stack is optional |

Each committer stack also runs a one-shot `init-db` container (`committer init-db`) that creates the
state database schema. Since committer v1.0.5 the validator no longer does this itself, so the
validator and query service wait for `init-db` to complete. It is idempotent, and the all-in-one
test-committer runs it internally.

## Version compatibility

| Orderer | Committer | Tools  | Block Explorer |   PostgreSQL    |
| :-----: | :-------: | :----: | :------------: | :-------------: |
| v1.0.6  |  v1.0.5   | v1.0.1 |     v0.1.2     | 18.3-alpine3.23 |

## Quick start

### Full stack (separate orderer and committer services)

```sh
make init                 # generate crypto and genesis block (run once, or after clean)
make start                # start orderers + Org1 committer
make start-explorer       # optional: block explorer UI at http://localhost:3000
make init-namespace       # create the namespace
```

Teardown:

```sh
make stop                # stop everything, including the explorer if running
make purge               # stop and delete all volumes
```

### Dev mode (single container, includes built-in orderer)

```sh
make init                # same init — crypto and genesis block are shared
make start-dev           # start the all-in-one test committer
make init-namespace      # same target — test-committer exposes the same service aliases
```

Teardown:

```sh
make stop-dev
```

`fxconfig.yaml` is identical for both modes. The test-committer answers on the same Docker
network aliases (`orderer-party1-router`, `committer-query-service`, `committer-sidecar`) as
the full-stack services, so applications need no changes when switching backends. One exception:
the full stack verifies client signatures (`ClientSignatureVerificationRequired: true` in the
router and batcher configs), so a submitted transaction must be signed by an identity that
satisfies the channel's `Writers` policy (a member of one of the orgs), or it is rejected at
broadcast. The mock orderer in dev mode does not check this, so test signing on the full stack.

### Block explorer (optional)

A web UI for browsing blocks and transactions
([fabric-x-block-explorer](https://github.com/LF-Decentralized-Trust-labs/fabric-x-block-explorer)).
It runs as two containers (combined UI+backend, PostgreSQL) and joins the `fabric-x` Docker network,
so a stack must be running first:

```sh
make start               # or start-dev / start-both
make start-explorer      # UI at http://localhost:3000
make stop-explorer       # stop only the explorer (stack keeps running)
```

`make stop` and `make purge` also stop the explorer; `make purge` additionally deletes its database.

## Using this network in your project

### Makefile (recommended)

Delegate network lifecycle to devnet from your own Makefile (this assumes `devnet` to be a subfolder
of your project, and your application starting with its own `compose.yaml`):

```makefile
DOCKER  ?= docker
COMPOSE ?= docker compose

.PHONY: init start stop purge

init:
    $(MAKE) -C devnet init

start:
    $(MAKE) -C devnet start
    $(MAKE) -C devnet init-namespace NS=myns POLICY="OR('Org1MSP.member')"
    $(COMPOSE) up -d

stop:
    $(COMPOSE) down
    $(MAKE) -C devnet stop

purge:
    $(COMPOSE) down
    $(MAKE) -C devnet purge
```

Your `compose.yaml` joins the external network created by devnet:

```yaml
services:
  my-app:
    # ...
    networks:
      - fabric-x

networks:
  fabric-x:
    external: true
```

### Docker Compose include (requires Compose v2.20+)

Alternatively, pull the devnet services directly into your compose project:

```yaml
include:
  - path: ./devnet/compose.yaml
  # - path: ./devnet/compose.org2.yaml   # optional

services:
  my-app:
    # ...
    networks:
      - fabric-x
    depends_on:
      - committer-query-service
```

Run `make -C devnet init` once, then `docker compose up -d` from your project root.

## Namespace init targets

Run one of these after the network is up:

| Target                     | Policy                                   |
| -------------------------- | ---------------------------------------- |
| `make init-namespace-org1` | `AND('Org1MSP.member')`                  |
| `make init-namespace-org2` | `AND('Org2MSP.member')`                  |
| `make init-namespace`      | `AND('Org1MSP.member','Org2MSP.member')` |

All targets are idempotent and work with both `start` and `start-dev`.
Override from the command line: `make init-namespace-org1 NS=myns POLICY="AND('Org1MSP.member')"`.

`make list-namespaces` queries the query service and prints all installed namespaces — useful as a connectivity check in CI.

## Running Org2's committer stack

Org2 is in the genesis block and its crypto material is generated by `make init`.
`make start` starts only Org1 by default. To bring up both orgs:

```sh
make start-both          # start orderers + Org1 and Org2 committers
```

## Rootless Podman

The standard targets are optimized for Docker and Rancher Desktop. For rootless Podman,
two adjustments are needed because user namespace remapping makes `user: "1000:1000"` in
compose map to a host subUID rather than your user — causing permission errors on
host-owned files.

**One-time setup** — start the Podman socket (required by `docker-compose`):

```sh
systemctl --user enable --now podman.socket
```

**Export these variables once** per shell session (or add to your shell profile):

```sh
export DOCKER=podman
export COMPOSE="podman compose"
export COMPOSE_OVERRIDE="-f compose.podman.yaml"
export RUN_AS=
```

`RUN_AS=` (empty) skips `--user` on `docker run` commands; container UID 0 = your host user
in rootless Podman. `compose.podman.yaml` sets `user: "0:0"` on the services for the same reason.

Then all standard targets work unchanged:

```sh
make init
make start
make start-explorer       # optional
make init-namespace
make stop      # or make purge
```

## Port reference

| Service                           | Host port              |
| --------------------------------- | ---------------------- |
| Router (broadcast), parties 1-4   | 7050, 7150, 7250, 7350 |
| Assembler (deliver), parties 1-4  | 7053, 7153, 7253, 7353 |
| Committer Sidecar (Org1)          | 4001                   |
| Committer Query Service (Org1)    | 7001                   |
| Committer Sidecar (Org2)          | 4002                   |
| Committer Query Service (Org2)    | 7002                   |
| Test committer (dev)              | 4001, 7001, 7050, 7053 |
| Block explorer UI (optional)      | 3000                   |
| Block explorer backend (optional) | 8080                   |

## Directory layout

```
.
├── crypto/                     # generated by make init (gitignored)
├── data/                       # bind mounts of the running network (gitignored)
├── config/                     # party{1-4}-{role}.yaml (orderer), committer-*.yaml, mock-orderer.yaml (dev), blockexplorer.yaml
├── .gitignore                  # ignores crypto/ and data/
├── compose.yaml                # 4-party Arma BFT orderer, plus 1 committer organization
├── compose.org2.yaml           # Org2 committer stack — optional, see below
├── compose.test-committer.yaml # all-in-one dev committer
├── compose.block-explorer.yaml # optional block explorer (UI + backend + db)
├── compose.podman.yaml         # override for rootless Podman, see below
├── crypto-config.yaml          # cryptogen input — all the certificates for the network
├── configtx.yaml               # channel topology and genesis block profile
├── shared_config.yaml          # Arma BFT party configuration
├── fxconfig.yaml               # client connection config — same file for both modes
└── Makefile
```

## Differences from a production network

This is a development network. Use
[fabric-x-ansible-collection](https://github.com/LF-Decentralized-Trust-labs/fabric-x-ansible-collection)
or similar for production deployments. However if you choose to use this as inspiration for a real deployment,
pay close attention to at least the following points.

- **Crypto:** generated by `cryptogen`, with every org's keys and CAs in one local `crypto/`
  directory. Use your own CAs and key management. The certificates are valid for 10 years and carry
  `localhost`, `host.docker.internal` and `0.0.0.0` SANs.
- **No roles in the identities:** NodeOUs are disabled and the policies only use `member` and
  `admin`, so nothing distinguishes the clients, endorsers and nodes of an org.
- **Secrets and transport:** database passwords are hard-coded in `config/`, and the database
  connections, the orderers' operations endpoints and most committer monitoring endpoints (all but
  the sidecar's) run without TLS. Published ports are bound on all host interfaces.
- **Genesis policies are permissive** (`configtx.yaml`): `LifecycleEndorsement` is
  `OR(Org1, Org2)`, so any single org can create or update namespaces, and the application `Admins`
  and `Endorsement` policies are `ANY`.
- **Topology and operations:** the four orderer parties (one batcher shard each) and a single
  instance of every committer service per org all run on one host. No monitoring, backup/restore,
  resource management, and so on.
- **Tuning:** batching favors low latency (`BatchCreationTimeout` 20ms) over
  throughput, and the verifier has more parallelism and a shorter batch cutoff than its defaults.
  The configs set only what is required or differs from the upstream defaults. For every other
  option, see the committer's commented
  [config samples](https://github.com/hyperledger/fabric-x-committer/tree/v1.0.5/cmd/config/samples)
  and [performance tuning guide](https://github.com/hyperledger/fabric-x-committer/blob/v1.0.5/docs/performance-tuning.md),
  and the orderer's commented
  [config template](https://github.com/hyperledger/fabric-x-orderer/blob/v1.0.6/config/sample/local_config.yaml).
