//go:build evm

/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package common

import (
	"errors"

	ftscore "github.com/LFDT-Panurus/panurus/token/core"
	"github.com/LFDT-Panurus/panurus/x/token/services/network/evm"
	"github.com/LFDT-Panurus/panurus/x/token/services/network/evm/endorsement"
	sdk "github.com/hyperledger-labs/fabric-smart-client/platform/common/sdk/dig"
	digutils "github.com/hyperledger-labs/fabric-smart-client/platform/common/utils/dig"
	"go.uber.org/dig"
)

// provideEVMDriver registers the EVM network driver, shared by PLATFORM=evm (sdk_evm_fabric.go)
// and PLATFORM=xevm (sdk_x_evm.go). Since Panurus v0.26.0 evm.NewDriver also takes an
// endorsement.PublicParamsValidator, which the token SDK does not provide; *core.TokenDriverService
// (which the token SDK does provide) implements it, so it is exposed under that interface too.
func provideEVMDriver(c sdk.Container) error {
	return errors.Join(
		c.Provide(
			digutils.Identity[*ftscore.TokenDriverService](),
			dig.As(new(endorsement.PublicParamsValidator)),
		),
		c.Provide(evm.NewDriver, dig.Group("network-drivers")),
	)
}
