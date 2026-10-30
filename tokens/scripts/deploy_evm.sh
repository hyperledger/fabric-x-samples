#!/usr/bin/env bash

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# Starts a standalone anvil chain in a container (unless one is already listening) and deploys the
# Panurus EVM token contracts against it for one TMS: an EndorsementVerifier holding the endorser
# set and threshold, a shared TokenState implementation, and a TokenState clone seeded with public
# parameters v0. This is the EVM-side counterpart of ./gen_crypto.sh's gen_parameters: run once per
# TMS, before the owner/issuer/endorser nodes start.
#
# The Panurus EVM module's own contracts/ directory lives in the (read-only) Go module cache and
# does not vendor forge-std (see its foundry.toml), so this script copies it into a writable
# workspace under EVM_DIR and fetches forge-std there before building.
#
# Usage: deploy_evm.sh <evm-dir> <public-params-file>
#   <evm-dir>            the gen_evm_keys.sh output directory (needs its addresses.env)
#   <public-params-file> the zkatdlognoghv1 public parameters file from ./gen_crypto.sh, reused
#                         as-is for the EVM leg's genesis public parameters (EVM_PP0)
#
# Writes <evm-dir>/deploy.env with EVM_VERIFIER_ADDRESS and EVM_TOKEN_STATE_ADDRESS, and funds
# every address in addresses.env from anvil's own default account 0.

set -e

EVM_DIR=$(realpath "${1:?usage: deploy_evm.sh <evm-dir> <public-params-file>}")
PP_FILE=$(realpath "${2:?usage: deploy_evm.sh <evm-dir> <public-params-file>}")
ANVIL_PORT="${ANVIL_PORT:-8545}"
ANVIL_CHAIN_ID="${ANVIL_CHAIN_ID:-31337}"
ANVIL_RPC="http://127.0.0.1:${ANVIL_PORT}"
ANVIL_LOG="${EVM_DIR}/anvil.log"
ANVIL_IMAGE="${ANVIL_IMAGE:-ghcr.io/foundry-rs/foundry:v1.8.1}"
# The app containers' network (fabric_test, or devnet's fabric-x for PLATFORM=xevm): anvil joins it
# so the nodes reach it as http://anvil:8545 by container name.
ANVIL_NETWORK="${TOKENS_NETWORK_NAME:-fabric_test}"
CONTAINER_CLI="${CONTAINER_CLI:-docker}"
WORKDIR="${EVM_DIR}/contracts"

# command -v curl/jq/forge/cast is assumed available, same as the rest of the sample's scripts.

## Start anvil in a container if nothing is already listening on ANVIL_PORT. Idempotent, so
## re-running this script against an already-running chain (e.g. during test_swap.sh iteration)
## does not spawn a second instance. A container on the app network rather than a host process:
## reaching the host from a container (host-gateway) is not portable across Docker runtimes
## (Rancher Desktop, for one, does not route it), container-to-container DNS is.
start_anvil() {
    if curl -s -o /dev/null "$ANVIL_RPC"; then
        echo "anvil already listening on ${ANVIL_PORT}, reusing it"
        return
    fi
    "$CONTAINER_CLI" rm -f anvil >/dev/null 2>&1 || true
    "$CONTAINER_CLI" run -d --name anvil --network "$ANVIL_NETWORK" -p "${ANVIL_PORT}:8545" \
        --entrypoint anvil "$ANVIL_IMAGE" --host 0.0.0.0 --port 8545 --chain-id "$ANVIL_CHAIN_ID" >/dev/null
    for _ in $(seq 1 30); do
        if curl -s -o /dev/null "$ANVIL_RPC"; then
            "$CONTAINER_CLI" logs anvil >"$ANVIL_LOG" 2>&1
            return
        fi
        sleep 1
    done
    "$CONTAINER_CLI" logs anvil >"$ANVIL_LOG" 2>&1 || true
    echo "Error: anvil did not come up on port ${ANVIL_PORT}; see ${ANVIL_LOG}" >&2
    exit 1
}

## Anvil's own account 0, printed to its log at startup. It is one of anvil's well-known,
## publicly documented dev-only keys (the same for every anvil instance unless --mnemonic is set),
## never appropriate outside a local throwaway chain like this one.
deployer_key() {
    grep -A3 "^Private Keys" "$ANVIL_LOG" | tail -1 | awk '{print $2}'
}

## Copy the module's contracts/ out of the (read-only) Go module cache into a writable workspace,
## and fetch forge-std there since the module does not vendor it (see foundry.toml).
prepare_workspace() {
    if [[ -d "$WORKDIR" ]]; then
        return
    fi
    local src
    src=$(go list -m -f '{{.Dir}}' github.com/LFDT-Panurus/panurus/x/token/services/network/evm)/contracts
    mkdir -p "$WORKDIR"
    cp -r "$src"/. "$WORKDIR"
    chmod -R u+w "$WORKDIR"
    # Pinned to the exact tag contracts/foundry.lock records, so the build matches what the module
    # was actually tested against instead of whatever forge-std's default branch has moved to.
    git clone --depth 1 --branch v1.16.2 https://github.com/foundry-rs/forge-std "${WORKDIR}/lib/forge-std"
}

build_contracts() {
    (cd "$WORKDIR" && forge build)
}

## Sends `amount` ETH from anvil's account 0 to `address`, so freshly generated endorser and
## submitter keys (which start with a zero balance) can pay for the transactions they sign.
fund() {
    local address=$1 amount=${2:-100}
    cast send --private-key "$(deployer_key)" --rpc-url "$ANVIL_RPC" --value "${amount}ether" "$address" >/dev/null
}

deploy() {
    # shellcheck disable=SC1091
    source "${EVM_DIR}/addresses.env"
    local pp0_hex
    # -c0 (unlimited line width) is not honored by every xxd build (some wrap at a fixed default
    # width regardless), so newlines are stripped explicitly rather than relied on not to appear -
    # vm.envBytes rejects a hex string broken across lines.
    pp0_hex="0x$(xxd -p "$PP_FILE" | tr -d '\n')"

    local deploy_log="${EVM_DIR}/deploy.log"
    (cd "$WORKDIR" && \
        EVM_ENDORSERS="${EVM_ENDORSER1_ADDRESS},${EVM_ENDORSER2_ADDRESS}" \
        EVM_THRESHOLD="${EVM_THRESHOLD:-2}" \
        EVM_PP0="$pp0_hex" \
        EVM_GRAPH_HIDING="${EVM_GRAPH_HIDING:-false}" \
        forge script script/Deploy.s.sol:Deploy \
            --rpc-url "$ANVIL_RPC" \
            --private-key "$(deployer_key)" \
            --broadcast) | tee "$deploy_log"

    local verifier token_state
    verifier=$(grep "EndorsementVerifier:" "$deploy_log" | awk '{print $2}')
    token_state=$(grep "TokenState clone:" "$deploy_log" | awk '{print $3}')
    if [[ -z "$verifier" || -z "$token_state" ]]; then
        echo "Error: could not parse the deployed contract addresses out of ${deploy_log}" >&2
        exit 1
    fi

    cat >"${EVM_DIR}/deploy.env" <<EOF
EVM_VERIFIER_ADDRESS=${verifier}
EVM_TOKEN_STATE_ADDRESS=${token_state}
EOF
    echo "EndorsementVerifier: ${verifier}"
    echo "TokenState clone: ${token_state}"
}

start_anvil
prepare_workspace
build_contracts

# shellcheck disable=SC1091
source "${EVM_DIR}/addresses.env"
for address in "$EVM_ENDORSER1_ADDRESS" "$EVM_ENDORSER2_ADDRESS" "$EVM_SUBMITTER_ISSUER_ADDRESS" "$EVM_SUBMITTER_OWNER1_ADDRESS" "$EVM_SUBMITTER_OWNER2_ADDRESS"; do
    fund "$address"
done

deploy
