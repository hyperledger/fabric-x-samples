//go:build fabricx

/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package common

import (
	"errors"

	common "github.com/hyperledger-labs/fabric-smart-client/platform/common/sdk/dig"
	digutils "github.com/hyperledger-labs/fabric-smart-client/platform/common/utils/dig"
	"github.com/hyperledger-labs/fabric-smart-client/platform/fabric/services/state"
	fabricxsdk "github.com/hyperledger-labs/fabric-smart-client/platform/fabricx/sdk/dig"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/services"
	dlog "github.com/LFDT-Panurus/panurus/token/core/zkatdlog/nogh/v1/driver"
	"github.com/LFDT-Panurus/panurus/token/sdk"
	tokensdk "github.com/LFDT-Panurus/panurus/token/sdk/dig"
	"github.com/LFDT-Panurus/panurus/token/services/network/fabricx"
	"github.com/LFDT-Panurus/panurus/token/services/network/fabricx/pp"
	"github.com/LFDT-Panurus/panurus/token/services/network/fabricx/tms"
	"go.uber.org/dig"
)

func NewSDK(registry services.Registry) *SDK {
	return &SDK{SDK: tokensdk.NewFrom(fabricxsdk.NewSDK(registry))}
}

type SDK struct {
	common.SDK
}

func (p *SDK) Install() error {
	err := errors.Join(
		sdk.RegisterTokenDriverDependencies(p.Container()),
		p.Container().Provide(dlog.NewTokenDriver, dig.Group("token-drivers")),
		p.Container().Provide(dlog.NewValidatorDriver, dig.Group("validator-drivers")),
		p.Container().Provide(fabricx.NewDriver, dig.Group("network-drivers")),
		p.Container().Provide(tms.NewSubmitterFromFNS, dig.As(new(tms.Submitter))),
		p.Container().Provide(tms.NewTMSDeployerService, dig.As(new(tms.DeployerService))),
		p.Container().Provide(pp.NewPublicParametersService),
		p.Container().Provide(digutils.Identity[*pp.PublicParametersService](), dig.As(new(pp.Loader))),
	)
	if err != nil {
		return err
	}
	if err := p.SDK.Install(); err != nil {
		return err
	}
	return errors.Join(
		digutils.Register[state.VaultService](p.Container()),
		digutils.Register[tms.DeployerService](p.Container()),
		digutils.Register[pp.Loader](p.Container()),
	)
}
