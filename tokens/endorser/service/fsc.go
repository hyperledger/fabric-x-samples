/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package service

import (
	"context"
	"fmt"
	"os"
	"reflect"

	"github.com/LFDT-Panurus/panurus/token/services/config"
	"github.com/LFDT-Panurus/panurus/token/services/network/fabricx/tms"
	"github.com/hyperledger-labs/fabric-smart-client/node"
	"github.com/hyperledger-labs/fabric-smart-client/platform/common/services/logging"
)

var logger = logging.MustGetLogger()

type FabricSmartClient struct {
	node *node.Node
}

func NewFSC(node *node.Node) *FabricSmartClient {
	return &FabricSmartClient{node: node}
}

// Init must be called for fabric-x networks to initialize the token parameters on the ledger.
//
// It deploys every TMS in core.yaml with the public parameters read from that TMS's
// publicParameters.path, rather than calling the deployer's DeployTMSs. DeployTMSs (still the
// case in Panurus v0.26.0) fetches the parameters to deploy from the ledger itself - the same
// reader used to load an already-initialized TMS - so on a fresh namespace it reads back
// nothing and commits an empty value.
//
// TMSs settled on an EVM chain (PLATFORM=xevm's evmtms) are skipped: their public parameters are
// seeded into the TokenState contract at deployment by scripts/deploy_evm.sh, not committed here.
func (f FabricSmartClient) Init(ctx context.Context) error {
	logger.Info("initializing token parameters")
	dep, err := tms.GetTMSDeployerService(f.node)
	if err != nil {
		return err
	}
	cs, err := f.node.GetService(reflect.TypeFor[*config.Service]())
	if err != nil {
		return fmt.Errorf("failed getting token config service: %w", err)
	}
	configs, err := cs.(*config.Service).Configurations()
	if err != nil {
		return fmt.Errorf("failed loading TMS configurations: %w", err)
	}

	for _, c := range configs {
		if c.IsSet("services.network.evm") {
			continue
		}
		path := c.GetString("publicParameters.path")
		if path == "" {
			return fmt.Errorf("no publicParameters.path configured for TMS [%s]", c.ID())
		}
		ppRaw, err := os.ReadFile(c.TranslatePath(path))
		if err != nil {
			return fmt.Errorf("failed reading public parameters for TMS [%s]: %w", c.ID(), err)
		}
		if err := dep.DeployTMSWithPP(c.ID(), ppRaw); err != nil {
			return fmt.Errorf("failed deploying TMS [%s]: %w", c.ID(), err)
		}
	}
	return nil
}
