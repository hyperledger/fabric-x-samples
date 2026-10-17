/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package service

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/hyperledger-labs/fabric-smart-client/node"
	"github.com/hyperledger-labs/fabric-smart-client/platform/common/services/logging"
	tmspkg "github.com/LFDT-Panurus/panurus/token"
	"github.com/LFDT-Panurus/panurus/token/services/network/fabricx/tms"
	"gopkg.in/yaml.v3"
)

var logger = logging.MustGetLogger()

type FabricSmartClient struct {
	node    *node.Node
	confDir string
}

func NewFSC(node *node.Node, confDir string) *FabricSmartClient {
	return &FabricSmartClient{node: node, confDir: confDir}
}

// Init must be called for fabric-x networks to initialize the token parameters on the ledger.
//
// DeployTMSs (Panurus v0.18.0) fetches the public parameters to deploy from the ledger itself
// (token/services/network/fabricx/tms/deployer.go's ppFetcher is the same reader used to load an
// *existing* TMS), so on a namespace that has never been initialized it reads back nothing and
// commits an empty value - a bootstrap that can never bootstrap. DeployTMSWithPP sidesteps that by
// taking the raw parameters directly, read here from the local file core.yaml's
// token.tms.mytms.publicParameters.path points at (the comment on that key is the original intent:
// "The endorser has the public parameters so it can commit them to the ledger").
func (f FabricSmartClient) Init(ctx context.Context) error {
	logger.Info("initializing token parameters")
	dep, err := tms.GetTMSDeployerService(f.node)
	if err != nil {
		return err
	}

	ppRaw, err := os.ReadFile(filepath.Join(f.confDir, "..", "namespace", "zkatdlognoghv1_pp.json"))
	if err != nil {
		return fmt.Errorf("failed reading public parameters: %w", err)
	}

	tmsID, err := f.tmsID()
	if err != nil {
		return err
	}
	if err := dep.DeployTMSWithPP(tmsID, ppRaw); err != nil {
		return err
	}
	return nil
}

// coreYAMLTokenConfig mirrors just enough of core.yaml's token.tms block to recover the TMS ID.
type coreYAMLTokenConfig struct {
	Token struct {
		TMS map[string]struct {
			Network   string `yaml:"network"`
			Channel   string `yaml:"channel"`
			Namespace string `yaml:"namespace"`
		} `yaml:"tms"`
	} `yaml:"token"`
}

// tmsID reads the network/channel/namespace to deploy to from core.yaml rather than hardcoding
// it: the channel name differs per platform (e.g. "arma" on the real Ansible-driven fabricx
// network, "mychannel" on devnet-based xdev), and this same binary runs on both.
func (f FabricSmartClient) tmsID() (tmspkg.TMSID, error) {
	raw, err := os.ReadFile(filepath.Join(f.confDir, "core.yaml"))
	if err != nil {
		return tmspkg.TMSID{}, fmt.Errorf("failed reading core.yaml: %w", err)
	}

	var cfg coreYAMLTokenConfig
	if err := yaml.Unmarshal(raw, &cfg); err != nil {
		return tmspkg.TMSID{}, fmt.Errorf("failed parsing core.yaml: %w", err)
	}

	for _, t := range cfg.Token.TMS {
		return tmspkg.TMSID{Network: t.Network, Channel: t.Channel, Namespace: t.Namespace}, nil
	}
	return tmspkg.TMSID{}, fmt.Errorf("no token.tms entries found in core.yaml")
}
