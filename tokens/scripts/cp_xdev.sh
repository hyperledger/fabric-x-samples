#!/usr/bin/env bash

set -exo pipefail

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

CONF_ROOT=$(realpath "${CONF_ROOT:-$(pwd)/conf}")
CRYPTO_DIR="${CRYPTO_DIR:-../devnet/crypto}"

echo "$CRYPTO_DIR"

for d in "${CONF_ROOT}"/*/ ; do
    rm -rf "$d/keys/fabric"
    rm -rf "$d/data" # data will be useless when we deleted the ledger
done

set -e

# Every node needs devnet's org1 TLS CA plus a client TLS cert/key chaining to it, to reach
# devnet's committer-sidecar/committer-query-service (both require mTLS) - devnet's own fxconfig
# tooling reuses the generic "fxconfig" peer identity's TLS material for exactly this, so we do
# the same rather than minting a separate one.
TLS_CA="${CRYPTO_DIR}/peerOrganizations/org1.example.com/msp/tlscacerts/tlsca.org1.example.com-cert.pem"
TLS_CLIENT="${CRYPTO_DIR}/peerOrganizations/org1.example.com/peers/fxconfig.org1.example.com/tls"

# Org1MSP fabric user (issuer/owner1/owner2, endorser1's endorsing identity) and Org2MSP fabric
# user (endorser2's endorsing identity) - for simplicity we reuse each org's one devnet-generated
# User1 identity for every role.
nodes=(issuer owner1 owner2 endorser1)
for node in "${nodes[@]}"; do
    dir="${CONF_ROOT}/${node}/keys/fabric"
    mkdir -p "${CONF_ROOT}/${node}/data"
    mkdir -p "$dir"

    cp -r "${CRYPTO_DIR}/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp" "$dir/user"
    cp -r "$TLS_CLIENT" "$dir/tls-client"
    cp "$TLS_CA" "$dir/org-tls-ca.pem"
done

# Endorser (see: https://github.com/hyperledger-labs/fabric-token-sdk/blob/main/docs/core-token.md?plain=1#L109).
dir="${CONF_ROOT}/endorser1/keys/fabric"
cp -r "${CRYPTO_DIR}/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp" "${dir}/endorser"

dir="${CONF_ROOT}/endorser2/keys/fabric"
mkdir -p "${CONF_ROOT}/endorser2/data"
mkdir -p "$dir"
cp -r "${CRYPTO_DIR}/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp" "${dir}/endorser"
cp -r "$TLS_CLIENT" "$dir/tls-client"
cp "$TLS_CA" "$dir/org-tls-ca.pem"

# Nodes that collect FSC-native endorsements (issuer for issue, owner1/owner2 for
# transfer/redeem) need a local copy of each endorser's endorsing MSP identity under
# fabric.default.msps, so common.BindEndorsingIdentities (see common/fsc.go) can bind it to
# the endorser's FSC/P2P identity at startup - required for the collect-endorsements view's
# IsBoundTo check to recognize a response signed with the endorsing identity as coming from
# the expected P2P party. Mirrors cp_fabric3.sh's identical step for fabric3.
for node in issuer owner1 owner2; do
    dir="${CONF_ROOT}/${node}/keys/fabric"
    cp -r "${CRYPTO_DIR}/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp" "${dir}/endorser1"
    cp -r "${CRYPTO_DIR}/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp" "${dir}/endorser2"
done
