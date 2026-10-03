#!/usr/bin/env bash

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# Brings up the EVM leg of the swap sample against an already-generated Fabric leg: generates the
# EVM endorser/submitter keys, deploys the token contracts to a standalone anvil chain seeded with
# the zkatdlognoghv1 public parameters ./gen_crypto.sh already produced, renders every node's
# core.yaml from its core.yaml.tmpl, and places each node's EVM key where its own core.yaml
# expects it. Run by PLATFORM=evm's start-fabric (see evm.mk), after `make setup` has already run
# gen_crypto.sh - this is the EVM-side counterpart of ./cp_fabric3.sh.
#
# Usage: setup_evm.sh <conf-root>

set -e

CONF_ROOT=$(realpath "${1:?usage: setup_evm.sh <conf-root>}")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PP_FILE="${CONF_ROOT}/namespace/zkatdlognoghv1_pp.json"
EVM_DIR="${CONF_ROOT}/evm"

if [[ ! -f "$PP_FILE" ]]; then
    echo "Error: ${PP_FILE} not found; run 'make setup' first so gen_crypto.sh generates it" >&2
    exit 1
fi

mkdir -p "$EVM_DIR"
"${SCRIPT_DIR}/gen_evm_keys.sh" "$EVM_DIR"
"${SCRIPT_DIR}/deploy_evm.sh" "$EVM_DIR" "$PP_FILE"

# shellcheck disable=SC1091
source "${EVM_DIR}/addresses.env"
# shellcheck disable=SC1091
source "${EVM_DIR}/deploy.env"
export EVM_ENDPOINT="${EVM_ENDPOINT:-http://anvil:8545}"
export EVM_CHAIN_ID="${EVM_CHAIN_ID:-31337}" # must match deploy_evm.sh's own ANVIL_CHAIN_ID default
export EVM_THRESHOLD="${EVM_THRESHOLD:-2}"
export EVM_TOKEN_STATE_ADDRESS EVM_VERIFIER_ADDRESS
export EVM_ENDORSER1_ADDRESS EVM_ENDORSER2_ADDRESS
export EVM_SUBMITTER_ISSUER_ADDRESS EVM_SUBMITTER_OWNER1_ADDRESS EVM_SUBMITTER_OWNER2_ADDRESS

for node in issuer owner1 owner2 endorser1 endorser2; do
    envsubst <"${CONF_ROOT}/${node}/core.yaml.tmpl" >"${CONF_ROOT}/${node}/core.yaml"
done

# Place each node's EVM identity where its rendered core.yaml's keystore path expects it.
for node in issuer owner1 owner2; do
    mkdir -p "${CONF_ROOT}/${node}/keys/evm"
done
cp "${EVM_DIR}/submitter-issuer.key" "${CONF_ROOT}/issuer/keys/evm/submitter.key"
cp "${EVM_DIR}/submitter-owner1.key" "${CONF_ROOT}/owner1/keys/evm/submitter.key"
cp "${EVM_DIR}/submitter-owner2.key" "${CONF_ROOT}/owner2/keys/evm/submitter.key"

for node in endorser1 endorser2; do
    mkdir -p "${CONF_ROOT}/${node}/keys/evm"
done
cp "${EVM_DIR}/endorser1.key" "${CONF_ROOT}/endorser1/keys/evm/endorser.key"
cp "${EVM_DIR}/endorser2.key" "${CONF_ROOT}/endorser2/keys/evm/endorser.key"

echo "EVM leg ready: TokenState ${EVM_TOKEN_STATE_ADDRESS}, EndorsementVerifier ${EVM_VERIFIER_ADDRESS}"
