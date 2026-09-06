#!/usr/bin/env bash

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

set -e
CONF_ROOT=$(realpath "${CONF_ROOT:-$(pwd)/conf-f3}")
FABRIC_SAMPLES="${FABRIC_SAMPLES:-..}"

# Org1MSP fabric user and peer TLS (for simplicity we use Org1MSP for all nodes)
nodes=(issuer owner1 owner2 endorser1 endorser2)
for node in "${nodes[@]}"; do
    dir="${CONF_ROOT}/${node}/keys/fabric"
    mkdir -p "$dir/user"
    mkdir -p "${CONF_ROOT}/${node}/data"

    cp -r "$FABRIC_SAMPLES/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp" "$dir/user"
    cp -r "$FABRIC_SAMPLES/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" "$dir/peer-tls-ca.crt"
done

# Endorsers (see: https://github.com/hyperledger-labs/fabric-token-sdk/blob/main/docs/core-token.md?plain=1#L109).
dir="${CONF_ROOT}/endorser1/keys/fabric"
mkdir -p "$dir"
cp -r "$FABRIC_SAMPLES/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/msp" "${dir}/endorser"

dir="${CONF_ROOT}/endorser2/keys/fabric"
mkdir -p "$dir"
cp -r "$FABRIC_SAMPLES/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/msp" "${dir}/endorser"

# Nodes that collect FSC-native endorsements (issuer for issue, owner1/owner2 for
# transfer/redeem) need a local copy of each endorser's endorsing MSP identity under
# fabric.default.msps, so common.BindEndorsingIdentities (see common/fsc.go) can bind it to
# the endorser's FSC/P2P identity at startup -- required for the collect-endorsements view's
# IsBoundTo check to recognize a response signed with the endorsing identity as coming from
# the expected P2P party.
for node in issuer owner1 owner2; do
    dir="${CONF_ROOT}/${node}/keys/fabric"
    cp -r "$FABRIC_SAMPLES/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/msp" "${dir}/endorser1"
    cp -r "$FABRIC_SAMPLES/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/msp" "${dir}/endorser2"
done
