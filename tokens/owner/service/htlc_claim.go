/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package service

import (
	"context"
	"encoding/json"

	"github.com/hyperledger-labs/fabric-smart-client/pkg/utils/errors"
	viewregistry "github.com/hyperledger-labs/fabric-smart-client/platform/view/services/view"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/view"

	"github.com/LFDT-Panurus/panurus/token"
	"github.com/LFDT-Panurus/panurus/token/services/interop/htlc"

	"github.com/hyperledger/fabric-samples/token-sdk/common/views"
)

// ClaimOptions contains the input information to claim a previously locked token.
type ClaimOptions struct {
	// TMSID identifies the TMS to use to perform the token operation. Nil selects the node's default TMS.
	TMSID *token.TMSID
	// Wallet is the identifier of the wallet to credit with the claimed token
	Wallet string
	// PreImage of the hash encoded in the htlc script of the token to be claimed
	PreImage []byte
}

type ClaimView struct {
	*ClaimOptions
}

func (v *ClaimView) Call(vctx view.Context) (any, error) {
	claimWallet := htlc.GetWallet(vctx, v.Wallet, views.ServiceOpts(v.TMSID)...)
	if claimWallet == nil {
		return nil, errors.Errorf("wallet [%s] not found", v.Wallet)
	}

	matched, err := htlc.Wallet(vctx, claimWallet).ListByPreImage(vctx.Context(), v.PreImage)
	if err != nil {
		return nil, errors.Wrap(err, "htlc script has expired or does not exist")
	}
	if matched.Count() != 1 {
		return nil, errors.Errorf("expected exactly one htlc script to match, got [%d]", matched.Count())
	}

	// Named transaction, not anonymous -- see htlc_lock.go's LockView for why.
	tx, err := htlc.NewTransaction(vctx, nil, views.TxOpts(v.TMSID)...)
	if err != nil {
		return nil, errors.Wrap(err, "failed creating htlc transaction")
	}
	if err := tx.Claim(vctx.Context(), claimWallet, matched.At(0), v.PreImage); err != nil {
		return nil, errors.Wrapf(err, "failed adding claim for [%s]", matched.At(0).Id)
	}

	if _, err := vctx.RunView(htlc.NewCollectEndorsementsView(tx)); err != nil {
		return nil, errors.Wrap(err, "failed to collect endorsements on htlc transaction")
	}
	if _, err := vctx.RunView(htlc.NewOrderingAndFinalityView(tx)); err != nil {
		return nil, errors.Wrap(err, "failed to commit htlc transaction")
	}

	return tx.ID(), nil
}

type ClaimViewFactory struct{}

func (f *ClaimViewFactory) NewView(in []byte) (view.View, error) {
	v := &ClaimView{ClaimOptions: &ClaimOptions{}}
	if err := json.Unmarshal(in, v.ClaimOptions); err != nil {
		return nil, errors.Wrap(err, "failed unmarshalling input")
	}
	return v, nil
}

// Claim claims a previously locked token using its pre-image, crediting the given wallet.
func (f FabricSmartClient) Claim(ctx context.Context, wallet string, preImage []byte) (txID string, err error) {
	logger.Infof("going to claim htlc token into [%s]", wallet)
	mgr, err := viewregistry.GetManager(f.node)
	if err != nil {
		return "", err
	}
	res, err := mgr.InitiateView(ctx, &ClaimView{
		ClaimOptions: &ClaimOptions{
			Wallet:   wallet,
			PreImage: preImage,
		},
	})
	if err != nil {
		logger.Errorf("error claiming: %s", err.Error())
		return "", err
	}
	txID, ok := res.(string)
	if !ok {
		return "", errors.New("cannot parse claim response")
	}
	logger.Infof("claimed htlc token into [%s]. ID: [%s]", wallet, txID)
	return txID, nil
}
