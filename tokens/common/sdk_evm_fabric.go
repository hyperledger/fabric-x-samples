//go:build evm

/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package common

import (
	"errors"

	common "github.com/hyperledger-labs/fabric-smart-client/platform/common/sdk/dig"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/services"
	dlog "github.com/LFDT-Panurus/panurus/token/core/zkatdlog/nogh/v1/driver"
	"github.com/LFDT-Panurus/panurus/token/sdk"
	tokensdk "github.com/LFDT-Panurus/panurus/token/sdk/dig"
	"github.com/LFDT-Panurus/panurus/token/services/network/fabric"
	"github.com/LFDT-Panurus/panurus/x/token/services/network/evm"
	"go.uber.org/dig"
)

// This file composes the PLATFORM=evm SDK: the same zkatdlog token and validator drivers as
// PLATFORM=fabric3, but with both the Fabric and EVM network drivers registered as
// "network-drivers". A node on this platform can therefore host a TMS on either network side by
// side - exactly what the swap sample needs, since the same owner has to lock on one network and
// claim on the other. Which driver a given TMS actually uses is decided per TMS by its own
// configuration (fabric.enabled / token.tms.<id>.services.network.evm), not by this file.
func NewSDK(registry services.Registry) *SDK {
	return &SDK{SDK: tokensdk.NewSDK(registry)}
}

type SDK struct {
	common.SDK
}

func (p *SDK) Install() error {
	err := errors.Join(
		sdk.RegisterTokenDriverDependencies(p.Container()),
		p.Container().Provide(fabric.NewGenericDriver, dig.Group("network-drivers")),
		p.Container().Provide(evm.NewDriver, dig.Group("network-drivers")),
		p.Container().Provide(dlog.NewTokenDriver, dig.Group("token-drivers")),
		p.Container().Provide(dlog.NewValidatorDriver, dig.Group("validator-drivers")),
	)
	if err != nil {
		return err
	}
	return p.SDK.Install()
}
