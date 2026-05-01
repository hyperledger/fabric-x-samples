/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"fmt"

	"github.com/hyperledger/fabric-x-samples/sdk-endorser/service"
	"github.com/hyperledger/fabric-x-sdk/endorsement"
)

// SampleExecutor is a very basic getter and setter that
// uses the SimulationStore to generate read/write sets.
type SampleExecutor struct{}

// Execute implements the service.Executor inteface.
func (SampleExecutor) Execute(ctx context.Context, newStore service.StoreFactory, inv endorsement.Invocation) (endorsement.ExecutionResult, error) {
	// Create a simulation store at the current blockheight.
	store, err := newStore(0)
	if err != nil {
		return endorsement.ExecutionResult{}, fmt.Errorf("simulation store: %w", err)
	}

	// The first argument is usually used as the "function".
	switch string(inv.Args[0]) {
	case "get":
		// You can create your own error types. The error message is returned to the caller.
		if len(inv.Args) < 2 {
			return endorsement.BadRequest("usage: get [key]"), nil
		}

		// GetState retrieves the state at the requested blockheight (latest by default).
		// The store is consistent, so that the state doesn't change as new blocks come in.
		res, err := store.GetState(string(inv.Args[1]))
		if err != nil {
			return endorsement.ExecutionResult{}, fmt.Errorf("db: %w", err)
		}

		// Return success, with the ReadWriteSet, an optional Fabric event and a payload message.
		// In this case the query result.
		return endorsement.Success(store.Result(), nil, res), nil

	case "set":
		// Bad request if not enough arguments were passed.
		if len(inv.Args) < 3 {
			return endorsement.BadRequest("usage: set [key] [value]"), nil
		}

		// PutState is a simulation. It's not stored in the database, but as a write
		// in the ReadWriteSet. store.Result() retrieves that ReadWriteSet.
		if err := store.PutState(string(inv.Args[1]), inv.Args[2]); err != nil {
			return endorsement.ExecutionResult{}, fmt.Errorf("db: %w", err)
		}

		// Return success.
		return endorsement.Success(store.Result(), nil, fmt.Appendf(nil, "%s=%s", string(inv.Args[1]), string(inv.Args[2]))), nil

	default:
		return endorsement.BadRequest("usage: get [key] || set [key] [value]"), nil
	}
}
