#!/usr/bin/env bash

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# End-to-end test for the HTLC swap between the Fabric and EVM legs of PLATFORM=evm: alice (owner1)
# holds TOK on the Fabric TMS (mytms), dan (owner2) holds ETOK on the anvil TMS (evmtms), and they
# trade across the two with a hash time-locked contract, each claiming the other's lock by
# revealing the same pre-image. A second scenario exercises the timeout/reclaim path when the
# counterparty never shows up.
#
# This is PLATFORM=evm only (it is the only platform with an evmtms); unlike scripts/test.sh it
# does not take PLATFORM from the environment.

CONTAINER_CLI="${CONTAINER_CLI:-docker}"
PLATFORM=evm
export PLATFORM

## Print a section title
function print_section_header() {
    echo "# ========================="
    echo "# $1"
    echo "# ========================="
}

## Cleanup and stop network on abort
function cleanup() {
    local exit_code=$?
    local failed_cmd="$BASH_COMMAND"
    # Command substitutions inherit the ERR trap; only the main shell should tear down the network
    [[ $BASHPID == "$$" ]] || exit "$exit_code"
    trap - INT ERR
    set +e
    stop_network
    echo "Error: command '$failed_cmd' exited with status $exit_code" >&2
    exit 1
}

## Setup and start the network (Fabric leg, anvil, contract deployment - see evm.mk)
function run_network() {
    print_section_header "Setup and start the network..."
    make setup start
}

## Stop and clean up the network
function stop_network() {
    print_section_header "Stopping network..."
    make teardown clean
}

## Wait for an API endpoint to report ready
function wait_until_ready() {
    local service_name="$1"
    local url="$2"
    local max_attempts="${MAX_READY_ATTEMPTS:-30}"
    local sleep_seconds="${READY_RETRY_SLEEP_SECONDS:-2}"
    local attempt=1

    while ! curl -fsS "$url" >/dev/null; do
        if (( attempt >= max_attempts )); then
            echo "Error: ${service_name} did not become ready after ${max_attempts} attempts (${url})" >&2
            return 1
        fi

        echo "Waiting for ${service_name} readiness (${attempt}/${max_attempts}): ${url}" >&2
        sleep "$sleep_seconds"
        ((attempt++))
    done
}

## Wait for all services needed by the test run
function wait_for_services() {
    print_section_header "Waiting for services to become ready..."
    wait_until_ready "issuer" "http://localhost:9100/readyz"
    wait_until_ready "owner1" "http://localhost:9500/readyz"
    wait_until_ready "owner2" "http://localhost:9600/readyz"
}

## Run curl with retries for transient startup errors
function curl_with_retry() {
    local max_attempts="${CURL_MAX_ATTEMPTS:-6}"
    local sleep_seconds="${CURL_RETRY_SLEEP_SECONDS:-2}"
    local attempt=1

    while true; do
        if curl -f -X "$@"; then
            return 0
        fi

        local exit_code=$?
        if (( attempt >= max_attempts )); then
            echo "Error: curl failed after ${attempt} attempts: curl -X $*" >&2
            return "$exit_code"
        fi

        echo "Retrying curl command (${attempt}/${max_attempts}): curl -X $*" >&2
        sleep "$sleep_seconds"
        ((attempt++))
    done
}

## Print the balance of an account on one TMS: get_balance <owner port> <account> <code> <tms query string>
## <tms query string> is e.g. "network=default&channel=mychannel&namespace=token_namespace"
function get_balance() {
    curl -sSf "http://localhost:$1/owner/accounts/$2?code=$3&$4" | jq -er '.payload.balance[0].value // 0'
}

## base64(SHA-256(base64 decoded input))
function sha256_b64() {
    printf '%s' "$1" | openssl base64 -d -A | openssl dgst -sha256 -binary | openssl base64 -A
}

## assert_eq <expected> <actual> <description>
function assert_eq() {
    if [[ "$1" != "$2" ]]; then
        echo "FAIL: $3: expected '$1', got '$2'" >&2
        return 1
    fi
    echo "OK: $3 ($2)"
}

## Poll until an account holds the expected balance on one TMS (finality is asynchronous on the
## non-initiating node). wait_for_balance <owner port> <account> <code> <tms query string> <expected> <description>
function wait_for_balance() {
    local port="$1" account="$2" code="$3" tms="$4" expected="$5" what="$6"
    local attempts="${BALANCE_MAX_ATTEMPTS:-15}" actual="" i
    for ((i = 1; i <= attempts; i++)); do
        actual=$(get_balance "$port" "$account" "$code" "$tms") || actual=""
        if [[ "$actual" == "$expected" ]]; then
            echo "OK: ${what}: ${account} holds ${actual} ${code}"
            return 0
        fi
        sleep 2
    done
    echo "FAIL: ${what}: expected ${account} to hold ${expected} ${code}, got ${actual}" >&2
    return 1
}

# TMS identifiers, as both a JSON object (lock/claim/reclaim/issue request bodies) and a query
# string (the balance endpoint's flat network/channel/namespace parameters).
MYTMS_JSON='{"network": "default", "channel": "mychannel", "namespace": "token_namespace"}'
MYTMS_QS='network=default&channel=mychannel&namespace=token_namespace'
EVMTMS_JSON='{"network": "evm", "channel": "", "namespace": "evm_namespace"}'
EVMTMS_QS='network=evm&channel=&namespace=evm_namespace'

## Issue tokens to seed both legs: alice gets TOK on mytms, dan gets ETOK on evmtms
function run_issuance() {
    print_section_header "Issue starting balances"
    curl_with_retry POST http://localhost:9100/issuer/issue -d '{
        "amount": {"code": "TOK", "value": 1000},
        "counterparty": {"node": "owner1", "account": "alice"},
        "tmsId": '"$MYTMS_JSON"'
    }' >/dev/null
    curl_with_retry POST http://localhost:9100/issuer/issue -d '{
        "amount": {"code": "ETOK", "value": 1000},
        "counterparty": {"node": "owner2", "account": "dan"},
        "tmsId": '"$EVMTMS_JSON"'
    }' >/dev/null
    wait_for_balance 9500 alice TOK "$MYTMS_QS" 1000 "issuance credited alice on Fabric"
    wait_for_balance 9600 dan ETOK "$EVMTMS_QS" 1000 "issuance credited dan on EVM"
}

## The successful swap: alice trades TOK (Fabric) for dan's ETOK (EVM)
function run_successful_swap() {
    print_section_header "Run the successful swap"

    local amount=200
    local secret secret_hash
    secret=$(openssl rand -base64 24)
    secret_hash=$(sha256_b64 "$secret")

    # Alice locks on the Fabric leg first, with the longer deadline: if she reveals the pre-image
    # late, dan still has margin to claim her lock before her own deadline lets her reclaim it too
    # and walk away with both sides. See the matching note in evmtms's config comments.
    curl_with_retry POST http://localhost:9500/owner/accounts/alice/lock -d '{
        "amount": {"code": "TOK", "value": '"$amount"'},
        "counterparty": {"node": "owner2", "account": "dan"},
        "deadline": 120,
        "hash": "'"$secret_hash"'",
        "tmsId": '"$MYTMS_JSON"'
    }' >/dev/null
    wait_for_balance 9500 alice TOK "$MYTMS_QS" 800 "alice's Fabric lock debited her"

    # Dan locks on the EVM leg for alice, with the shorter deadline.
    curl_with_retry POST http://localhost:9600/owner/accounts/dan/lock -d '{
        "amount": {"code": "ETOK", "value": '"$amount"'},
        "counterparty": {"node": "owner1", "account": "alice"},
        "deadline": 60,
        "hash": "'"$secret_hash"'",
        "tmsId": '"$EVMTMS_JSON"'
    }' >/dev/null
    wait_for_balance 9600 dan ETOK "$EVMTMS_QS" 800 "dan's EVM lock debited him"

    # Alice claims dan's EVM lock, revealing the pre-image on chain.
    curl_with_retry POST http://localhost:9500/owner/accounts/alice/claim -d '{
        "preimage": "'"$secret"'",
        "tmsId": '"$EVMTMS_JSON"'
    }' >/dev/null
    wait_for_balance 9500 alice ETOK "$EVMTMS_QS" "$amount" "alice's claim credited her on EVM"

    # Dan claims alice's Fabric lock using the now-public pre-image.
    curl_with_retry POST http://localhost:9600/owner/accounts/dan/claim -d '{
        "preimage": "'"$secret"'",
        "tmsId": '"$MYTMS_JSON"'
    }' >/dev/null
    wait_for_balance 9600 dan TOK "$MYTMS_QS" "$amount" "dan's claim credited him on Fabric"

    echo "Swap complete: alice now holds ${amount} ETOK, dan now holds ${amount} TOK"
}

## The counterparty-never-shows-up path: alice locks, nobody claims, alice reclaims after the
## deadline on the chain she locked on. Single-chain by design - the swap never reached its second
## leg, so there is nothing to unwind on the EVM side.
function run_timeout_reclaim() {
    print_section_header "Run the timeout/reclaim path"

    local amount=50 deadline=8
    local alice_before secret secret_hash
    secret=$(openssl rand -base64 24)
    secret_hash=$(sha256_b64 "$secret")
    alice_before=$(get_balance 9500 alice TOK "$MYTMS_QS")

    curl_with_retry POST http://localhost:9500/owner/accounts/alice/lock -d '{
        "amount": {"code": "TOK", "value": '"$amount"'},
        "counterparty": {"node": "owner2", "account": "dan"},
        "deadline": '"$deadline"',
        "hash": "'"$secret_hash"'",
        "tmsId": '"$MYTMS_JSON"'
    }' >/dev/null
    wait_for_balance 9500 alice TOK "$MYTMS_QS" $((alice_before - amount)) "lock debited alice"

    echo "Waiting $((deadline + 5))s for the lock to expire without a counterparty..."
    sleep $((deadline + 5))
    curl_with_retry POST http://localhost:9500/owner/accounts/alice/reclaim -d '{
        "hash": "'"$secret_hash"'",
        "tmsId": '"$MYTMS_JSON"'
    }' >/dev/null
    wait_for_balance 9500 alice TOK "$MYTMS_QS" "$alice_before" "reclaim restored alice"
}

# Script Start
set -eE
set -o pipefail
trap cleanup INT ERR

run_network
sleep 10
wait_for_services
run_issuance
run_successful_swap
run_timeout_reclaim
stop_network
