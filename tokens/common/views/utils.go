/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package views

import (
	"context"
	"strings"

	"github.com/hyperledger-labs/fabric-smart-client/platform/common/utils/assert"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/view"
	"github.com/LFDT-Panurus/panurus/token"
	"github.com/LFDT-Panurus/panurus/token/services/storage/tokendb"
	"github.com/LFDT-Panurus/panurus/token/services/ttx"
)

// AssertTokens checks that the tokens are or are not in the tokendb
func AssertTokens(sp token.ServiceProvider, tx *ttx.Transaction, outputs *token.OutputStream, id view.Identity) {
	ctx := context.Background()
	db, err := tokendb.GetByTMSId(sp, tx.TokenService().ID())
	assert.NoError(err, "failed to get token db for [%s]", tx.TokenService().ID())
	for _, output := range outputs.Outputs() {
		tokenID := output.ID(token.RequestAnchor(tx.ID()))
		if output.Owner.Equal(id) || tx.TokenService().SigService().IsMe(ctx, output.Owner) {
			// check it exists
			toks, err := db.GetTokens(ctx, tokenID)
			assert.NoError(err, "failed to retrieve token [%s]", tokenID)
			assert.Equal(1, len(toks), "expected one token")
			assert.Equal(output.Quantity.Hex(), toks[0].Quantity, "token quantity mismatch")
			assert.Equal(output.Type, toks[0].Type, "token type mismatch")
		} else {
			// check it does not exist
			_, err := db.GetTokens(ctx, tokenID)
			assert.Error(err, "token [%s] should not exist", tokenID)
			assert.True(strings.Contains(err.Error(), "token not found"))
		}
	}
}

// ServiceOpts creates a new array of token.ServiceOption containing token.WithTMSID and any additional token.ServiceOption passed to this function
func ServiceOpts(tmsId *token.TMSID, opts ...token.ServiceOption) []token.ServiceOption {
	var serviceOpts []token.ServiceOption
	if tmsId != nil {
		serviceOpts = append(serviceOpts, token.WithTMSID(*tmsId))
	}

	return append(serviceOpts, opts...)
}

func TxOpts(tmsId *token.TMSID, opts ...ttx.TxOption) []ttx.TxOption {
	var txOpts []ttx.TxOption
	if tmsId != nil {
		txOpts = append(txOpts, ttx.WithTMSID(*tmsId))
	}
	txOpts = append(txOpts, opts...)

	return txOpts
}
