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

// ReclaimOptions contains the input information to reclaim a single expired locked token.
type ReclaimOptions struct {
	// TMSID identifies the TMS to use to perform the token operation. Nil selects the node's default TMS.
	TMSID *token.TMSID
	// Wallet is the identifier of the wallet that owns the expired lock
	Wallet string
	// Hash is the hash of the lock to reclaim
	Hash []byte
}

type ReclaimView struct {
	*ReclaimOptions
}

func (v *ReclaimView) Call(vctx view.Context) (any, error) {
	senderWallet := htlc.GetWallet(vctx, v.Wallet, views.ServiceOpts(v.TMSID)...)
	if senderWallet == nil {
		return nil, errors.Errorf("sender wallet [%s] not found", v.Wallet)
	}

	expired, err := htlc.Wallet(vctx, senderWallet).GetExpiredByHash(vctx.Context(), v.Hash)
	if err != nil {
		return nil, errors.Wrap(err, "cannot retrieve expired htlc token")
	}

	// Named transaction, not anonymous -- see htlc_lock.go's LockView for why.
	tx, err := htlc.NewTransaction(vctx, nil, views.TxOpts(v.TMSID)...)
	if err != nil {
		return nil, errors.Wrap(err, "failed creating htlc transaction")
	}
	if err := tx.Reclaim(vctx.Context(), senderWallet, expired); err != nil {
		return nil, errors.Wrapf(err, "failed adding reclaim for [%s]", expired.Id)
	}

	if _, err := vctx.RunView(htlc.NewCollectEndorsementsView(tx)); err != nil {
		return nil, errors.Wrap(err, "failed to collect endorsements on htlc transaction")
	}
	if _, err := vctx.RunView(htlc.NewOrderingAndFinalityView(tx)); err != nil {
		return nil, errors.Wrap(err, "failed to commit htlc transaction")
	}

	return tx.ID(), nil
}

type ReclaimViewFactory struct{}

func (f *ReclaimViewFactory) NewView(in []byte) (view.View, error) {
	v := &ReclaimView{ReclaimOptions: &ReclaimOptions{}}
	if err := json.Unmarshal(in, v.ReclaimOptions); err != nil {
		return nil, errors.Wrap(err, "failed unmarshalling input")
	}
	return v, nil
}

// Reclaim reclaims a single expired locked token identified by hash, crediting it back to the given wallet.
func (f FabricSmartClient) Reclaim(ctx context.Context, wallet string, hash []byte) (txID string, err error) {
	logger.Infof("going to reclaim htlc token into [%s]", wallet)
	mgr, err := viewregistry.GetManager(f.node)
	if err != nil {
		return "", err
	}
	res, err := mgr.InitiateView(ctx, &ReclaimView{
		ReclaimOptions: &ReclaimOptions{
			Wallet: wallet,
			Hash:   hash,
		},
	})
	if err != nil {
		logger.Errorf("error reclaiming: %s", err.Error())
		return "", err
	}
	txID, ok := res.(string)
	if !ok {
		return "", errors.New("cannot parse reclaim response")
	}
	logger.Infof("reclaimed htlc token into [%s]. ID: [%s]", wallet, txID)
	return txID, nil
}
