#!/usr/bin/env bash

#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

CONTAINER_CLI="${CONTAINER_CLI:-docker}"

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

## Setup and start the network
function run_network() {
    print_section_header "Setup and start the network..."
    make setup start
}

## Stop and clean up the network
function stop_network() {
    print_section_header "Stopping network..."
    make teardown clean
}

## Initialize FabricX if needed
function init_fabricx() {
    print_section_header "Initializing ${PLATFORM}..."
    # The endorser's readyz only reports its own HTTP server is up, not that the
    # underlying Fabric-X network (real deployments run ~20 orderer/committer
    # containers) has finished converging enough to accept the setup transaction
    # this triggers -- so the first call(s) here routinely 500 right after startup.
    # Retry with a longer window than curl_with_retry's default.
    CURL_MAX_ATTEMPTS=30 CURL_RETRY_SLEEP_SECONDS=5 curl_with_retry POST http://localhost:9300/endorser/init
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

    if [[ "$PLATFORM" == "fabricx" || "$PLATFORM" == "xdev" ]]; then
        wait_until_ready "endorser" "http://localhost:9300/readyz"
    fi

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

## Run tests to verify the network
function run_test() {
    # test application
    print_section_header "Run tests"

    curl_with_retry POST http://localhost:9100/issuer/issue -d '{
        "amount": {"code": "TOK","value": 1000},
        "counterparty": {"node": "owner1","account": "alice"},
        "message": "hello world!"
    }'
    curl_with_retry GET http://localhost:9500/owner/accounts/alice | jq
    curl_with_retry GET http://localhost:9600/owner/accounts/dan | jq
    curl_with_retry POST http://localhost:9500/owner/accounts/alice/transfer -d '{
        "amount": {"code": "TOK","value": 100},
        "counterparty": {"node": "owner2","account": "dan"},
        "message": "hello dan!"
    }'
    curl_with_retry GET http://localhost:9600/owner/accounts/dan/transactions | jq
    curl_with_retry GET http://localhost:9500/owner/accounts/alice/transactions | jq
    curl_with_retry POST http://localhost:9500/owner/accounts/alice/redeem -d '{
        "amount": {"code": "TOK","value": 50},
        "message": "redeem test"
    }'
    curl_with_retry GET http://localhost:9500/owner/accounts/alice | jq
}

## Token SDK channel of the default TMS for the selected platform
function tms_channel() {
    case "$PLATFORM" in
        fabric3) echo "mychannel" ;;
        *) echo "arma" ;;
    esac
}

## Print the balance of an account: get_balance <owner port> <account> <token code>
function get_balance() {
    curl -sSf "http://localhost:$1/owner/accounts/$2?code=$3" | jq -er '.payload.balance[0].value // 0'
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

## Poll until an account holds the expected balance (finality is asynchronous on the non-initiating node)
## wait_for_balance <owner port> <account> <token code> <expected balance> <description>
function wait_for_balance() {
    local port="$1" account="$2" code="$3" expected="$4" what="$5"
    local attempts="${BALANCE_MAX_ATTEMPTS:-15}" actual="" i
    for ((i = 1; i <= attempts; i++)); do
        actual=$(get_balance "$port" "$account" "$code")
        if [[ "$actual" == "$expected" ]]; then
            echo "OK: ${what}: ${account} holds ${actual} ${code}"
            return 0
        fi
        sleep 2
    done
    echo "FAIL: ${what}: expected ${account} to hold ${expected} ${code}, got ${actual}" >&2
    return 1
}

## Succeeds only if the server rejects the request (HTTP status >= 400).
## Plain curl on purpose: curl_with_retry would retry the request.
## expect_http_error <method> <url> [curl args...]
function expect_http_error() {
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' -X "$@") || true # 000 on a connection error, which is not a rejection
    if (( 10#${status:-0} >= 400 )); then
        echo "OK: request was rejected with HTTP ${status} as expected"
        return 0
    fi
    echo "FAIL: expected the request to be rejected, got HTTP ${status}" >&2
    return 1
}

## Run the HTLC (hash time-locked contract) tests: lock, claim and reclaim
function run_htlc_test() {
    print_section_header "Run HTLC tests"

    local amount=20 deadline="${HTLC_DEADLINE:-10}"
    local tms
    tms='{"network": "default", "channel": "'"$(tms_channel)"'", "namespace": "token_namespace"}'
    local alice_before dan_before lock preimage hash secret secret_hash

    # 1. Node generated pre-image and an explicit TMS: alice locks for dan, dan claims
    alice_before=$(get_balance 9500 alice TOK)
    dan_before=$(get_balance 9600 dan TOK)
    lock=$(curl_with_retry POST http://localhost:9500/owner/accounts/alice/lock -d '{
        "amount": {"code": "TOK", "value": '"$amount"'},
        "counterparty": {"node": "owner2", "account": "dan"},
        "deadline": 3600,
        "tmsId": '"$tms"'
    }')
    preimage=$(jq -er '.payload.preimage' <<<"$lock")
    hash=$(jq -er '.payload.hash' <<<"$lock")
    assert_eq "$(sha256_b64 "$preimage")" "$hash" "lock returned the SHA-256 of the pre-image"
    curl_with_retry POST http://localhost:9600/owner/accounts/dan/claim -d '{
        "preimage": "'"$preimage"'",
        "tmsId": '"$tms"'
    }' >/dev/null
    wait_for_balance 9600 dan TOK $((dan_before + amount)) "claim credited dan"
    wait_for_balance 9500 alice TOK $((alice_before - amount)) "lock debited alice"

    # 2. Caller supplied hash and the default TMS: alice locks for dan with a short deadline, nobody claims
    # in time, alice reclaims, and dan's late claim is rejected
    secret=$(openssl rand -base64 24)
    secret_hash=$(sha256_b64 "$secret")
    alice_before=$(get_balance 9500 alice TOK)
    lock=$(curl_with_retry POST http://localhost:9500/owner/accounts/alice/lock -d '{
        "amount": {"code": "TOK", "value": '"$amount"'},
        "counterparty": {"node": "owner2", "account": "dan"},
        "deadline": '"$deadline"',
        "hash": "'"$secret_hash"'"
    }')
    if ! jq -e --arg h "$secret_hash" '.payload.hash == $h and (.payload | has("preimage") | not)' <<<"$lock" >/dev/null; then
        echo "FAIL: expected the lock to echo the supplied hash and return no pre-image, got: $lock" >&2
        return 1
    fi
    wait_for_balance 9500 alice TOK $((alice_before - amount)) "second lock debited alice"
    echo "Waiting $((deadline + 5))s for the lock to expire..."
    sleep $((deadline + 5))
    curl_with_retry POST http://localhost:9500/owner/accounts/alice/reclaim -d '{"hash": "'"$secret_hash"'"}' >/dev/null
    wait_for_balance 9500 alice TOK "$alice_before" "reclaim restored alice"
    dan_before=$(get_balance 9600 dan TOK)
    expect_http_error POST http://localhost:9600/owner/accounts/dan/claim -d '{"preimage": "'"$secret"'"}'
    wait_for_balance 9600 dan TOK "$dan_before" "rejected claim left dan unchanged"
}

# Script Start
set -eE
set -o pipefail
trap cleanup INT ERR
PLATFORM="${PLATFORM:-fabric3}"
export PLATFORM

run_network
# # currently we wait manually with a sleep.
# # TODO: add an healthcheck within the `docker-compose`
sleep 10
wait_for_services
if [[ "$PLATFORM" == "fabricx" || "$PLATFORM" == "xdev" ]]; then
    init_fabricx
fi
run_test
# The HTLC tests run on fabric3 by default; set HTLC_TEST=1 to run them on other platforms too
if [[ "$PLATFORM" == "fabric3" || "${HTLC_TEST:-}" == "1" ]]; then
    run_htlc_test
else
    echo "Skipping HTLC tests on ${PLATFORM} (set HTLC_TEST=1 to run them)"
fi
stop_network