#!/usr/bin/env bash

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# Generates the secp256k1 identities the EVM leg of the swap sample needs: one key per EVM
# endorser (bound to an existing FSC endorser identity, never reusing its Fabric MSP key) and one
# submitter key per node that submits its own transactions and pays their gas (the issuer, issuing
# on the EVM TMS, and each owner, locking/claiming/reclaiming on it). Each is a fresh, locally
# generated scalar, written as a hex file in the format x/token/services/network/evm's
# keystore.LoadKey expects (plain hex, optionally 0x-prefixed), never committed and never reused
# across runs.
#
# Usage: gen_evm_keys.sh <output-dir>
# Writes, under <output-dir>: endorser1.key, endorser2.key, submitter-issuer.key,
# submitter-owner1.key, submitter-owner2.key, and addresses.env (the derived 0x address for each,
# as shell assignments that deploy_evm.sh and the conf-evm core.yaml templates consume).

set -e

OUT_DIR=$(realpath "${1:?usage: gen_evm_keys.sh <output-dir>}")
mkdir -p "$OUT_DIR"

names=(endorser1 endorser2 submitter-issuer submitter-owner1 submitter-owner2)

addresses_file="${OUT_DIR}/addresses.env"
: >"$addresses_file"

for name in "${names[@]}"; do
    key_file="${OUT_DIR}/${name}.key"
    openssl rand -hex 32 >"$key_file"
    chmod 600 "$key_file"

    address=$(cast wallet address "0x$(cat "$key_file")")
    var_name=$(echo "EVM_${name}_ADDRESS" | tr '[:lower:]-' '[:upper:]_')
    echo "${var_name}=${address}" >>"$addresses_file"
    echo "generated ${name}: ${address} (key: ${key_file})"
done

echo "addresses written to ${addresses_file}"
