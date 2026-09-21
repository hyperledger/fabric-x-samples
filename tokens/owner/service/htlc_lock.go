/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package service

import (
	"context"
	"encoding/json"
	"time"

	"github.com/hyperledger-labs/fabric-smart-client/pkg/utils/errors"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/services/endpoint"
	viewregistry "github.com/hyperledger-labs/fabric-smart-client/platform/view/services/view"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/view"

	"github.com/LFDT-Panurus/panurus/token"
	"github.com/LFDT-Panurus/panurus/token/services/interop/htlc"
	tok "github.com/LFDT-Panurus/panurus/token/token"

	"github.com/hyperledger/fabric-samples/token-sdk/common/views"
)

// LockOptions contains the input information to lock a token in an HTLC script.
type LockOptions struct {
	// TMSID identifies the TMS to use to perform the token operation. Nil selects the node's default TMS.
	TMSID *token.TMSID
	// Wallet is the identifier of the wallet that owns the tokens to lock
	Wallet string
	// TokenType of tokens to lock
	TokenType string
	// Quantity to lock
	Quantity uint64
	// Recipient is the identity of the recipient's wallet
	Recipient string
	// RecipientNode is the identity of the recipient's FSC node. Empty for a same-node lock.
	RecipientNode string
	// Hash is the hash to use in the script; if nil, a fresh one is generated from a random pre-image
	Hash []byte
	// ReclamationDeadline is how long from now the locker can reclaim the funds if they are not claimed
	ReclamationDeadline time.Duration
}

// LockResult is returned once a lock transaction has been ordered and confirmed.
type LockResult struct {
	TxID     string
	PreImage []byte
	Hash     []byte
}

type LockView struct {
	*LockOptions
}

func (v *LockView) Call(vctx view.Context) (any, error) {
	// Internal transaction: identity must exist in a wallet
	if v.RecipientNode != "" {
		// Bind the recipient identity name to its node so FSC knows who to contact.
		if err := endpoint.GetService(vctx).Bind(vctx.Context(), view.Identity(v.RecipientNode), view.Identity(v.Recipient)); err != nil {
			return nil, errors.Wrap(err, "failed binding recipient to node")
		}
	}

	// The lock script records both the sender's and the recipient's identity, so both sides
	// must agree on the same pair -- htlc's own exchange, not fsc.go's getRemoteIdentity, is
	// what guarantees that.
	me, recipient, err := htlc.ExchangeRecipientIdentities(vctx, v.Wallet, view.Identity(v.Recipient), views.ServiceOpts(v.TMSID)...)
	if err != nil {
		return nil, errors.Wrap(err, "failed exchanging recipient identity")
	}

	// This app doesn't set up an anonymous FSC-native identity (idemix) anywhere else, so use
	// a named transaction here too, matching TransferView/RedeemView's own pattern, rather than
	// htlc.NewAnonymousTransaction (the reference's choice, which needs that identity).
	tx, err := htlc.NewTransaction(vctx, nil, views.TxOpts(v.TMSID)...)
	if err != nil {
		return nil, errors.Wrap(err, "failed creating htlc transaction")
	}

	senderWallet := htlc.GetWallet(vctx, v.Wallet, views.ServiceOpts(v.TMSID)...)
	if senderWallet == nil {
		return nil, errors.Errorf("sender wallet [%s] not found", v.Wallet)
	}

	preImage, err := tx.Lock(vctx.Context(), senderWallet, me, tok.Type(v.TokenType), v.Quantity, recipient, v.ReclamationDeadline, htlc.WithHash(v.Hash))
	if err != nil {
		return nil, errors.Wrap(err, "failed adding lock operation")
	}

	if _, err := vctx.RunView(htlc.NewCollectEndorsementsView(tx)); err != nil {
		return nil, errors.Wrap(err, "failed to collect endorsements for htlc transaction")
	}
	if _, err := vctx.RunView(htlc.NewOrderingAndFinalityView(tx)); err != nil {
		return nil, errors.Wrap(err, "failed to commit htlc transaction")
	}

	outputs, err := tx.Outputs(vctx.Context())
	if err != nil {
		return nil, errors.Wrap(err, "failed getting outputs")
	}

	return &LockResult{
		TxID:     tx.ID(),
		PreImage: preImage,
		Hash:     outputs.ScriptAt(0).HashInfo.Hash,
	}, nil
}

type LockViewFactory struct{}

func (f *LockViewFactory) NewView(in []byte) (view.View, error) {
	v := &LockView{LockOptions: &LockOptions{}}
	if err := json.Unmarshal(in, v.LockOptions); err != nil {
		return nil, errors.Wrap(err, "failed unmarshalling input")
	}
	return v, nil
}

// LockAcceptView is the recipient-side responder in a lock flow: it exchanges identities with
// the locker, receives the prepared lock transaction, validates the script names it as
// recipient, and accepts.
type LockAcceptView struct{}

func (a *LockAcceptView) Call(vctx view.Context) (any, error) {
	me, sender, err := htlc.RespondExchangeRecipientIdentities(vctx)
	if err != nil {
		return nil, errors.Wrap(err, "failed to respond to identity exchange")
	}

	tx, err := htlc.ReceiveTransaction(vctx)
	if err != nil {
		return nil, errors.Wrap(err, "failed to receive htlc transaction")
	}

	outputs, err := tx.Outputs(vctx.Context())
	if err != nil {
		return nil, errors.Wrap(err, "failed getting outputs")
	}
	scripted := outputs.ByScript()
	if scripted.Count() != 1 {
		return nil, errors.Errorf("expected exactly one htlc output, got [%d]", scripted.Count())
	}

	script := scripted.ScriptAt(0)
	if err := script.Validate(time.Now()); err != nil {
		return nil, errors.Wrap(err, "script is not valid")
	}
	if !me.Equal(script.Recipient) {
		return nil, errors.Errorf("expected me as recipient of the script")
	}
	if !sender.Equal(script.Sender) {
		return nil, errors.Errorf("expected sender as sender of the script")
	}

	if _, err := vctx.RunView(htlc.NewAcceptView(tx)); err != nil {
		return nil, errors.Wrap(err, "failed to accept locked tokens")
	}
	if _, err := vctx.RunView(htlc.NewFinalityView(tx)); err != nil {
		return nil, errors.Wrap(err, "locked tokens were not committed")
	}

	return tx.ID(), nil
}

// Lock locks an amount of a certain token type into an HTLC script, returning the pre-image the
// locker must pass to the claimer out of band, and the hash the claimer/reclaimer will reference.
func (f FabricSmartClient) Lock(ctx context.Context, tokenType string, quantity uint64, sender string, recipient string, recipientNode string, deadline time.Duration, hash []byte) (LockResult, error) {
	logger.Infof("going to lock %d %s from [%s] for [%s] on [%s]", quantity, tokenType, sender, recipient, recipientNode)
	mgr, err := viewregistry.GetManager(f.node)
	if err != nil {
		return LockResult{}, err
	}
	res, err := mgr.InitiateView(ctx, &LockView{
		LockOptions: &LockOptions{
			Wallet:              sender,
			TokenType:           tokenType,
			Quantity:            quantity,
			Recipient:           recipient,
			RecipientNode:       recipientNode,
			Hash:                hash,
			ReclamationDeadline: deadline,
		},
	})
	if err != nil {
		logger.Errorf("error locking: %s", err.Error())
		return LockResult{}, err
	}
	result, ok := res.(*LockResult)
	if !ok {
		return LockResult{}, errors.New("cannot parse lock response")
	}
	logger.Infof("locked %d %s from [%s] for [%s]. ID: [%s]", quantity, tokenType, sender, recipient, result.TxID)
	return *result, nil
}
