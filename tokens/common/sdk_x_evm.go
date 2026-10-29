//go:build fabricx && evm

/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package common

// PLATFORM=xevm: the Fabric-X SDK (sdk_x.go) plus the EVM network driver, so a node can host a
// TMS on Fabric-X and one on an EVM chain side by side - the Fabric-X counterpart of
// PLATFORM=evm's sdk_evm_fabric.go. Which driver a TMS uses is decided by its own configuration.
func init() {
	extraNetworkDrivers = append(extraNetworkDrivers, provideEVMDriver)
}
