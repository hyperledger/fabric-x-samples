/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package common

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/hyperledger-labs/fabric-smart-client/node"
	"github.com/hyperledger-labs/fabric-smart-client/platform/fabric"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/services/endpoint"
	"github.com/hyperledger-labs/fabric-smart-client/platform/view/services/id"
)

// StartFSC starts a new node.
func StartFSC(confPath, datadir string) (*node.Node, error) {
	if len(datadir) != 0 {
		if err := os.MkdirAll(datadir, 0755); err != nil {
			return nil, fmt.Errorf("error creating data directory %s: %w", datadir, err)
		}
	}

	fsc := node.NewWithConfPath(confPath)
	if err := fsc.InstallSDK(NewSDK(fsc)); err != nil {
		return nil, fmt.Errorf("error installing fsc: %w", err)
	}
	if err := fsc.Start(); err != nil {
		return nil, fmt.Errorf("error starting fsc: %w", err)
	}

	return fsc, nil
}

// BindEndorsingIdentities binds each endorser's Fabric endorsing (MSP) identity, declared
// in fabric.default.msps under mspLabel, to its FSC/P2P identity, declared in
// fsc.endpoint.resolvers under p2pName. The FSC-native endorsement collection path
// (token.tms.<tms>.services.network.fabric.fsc_endorsement) checks that a response is
// signed by, or bound to, the party it contacted; since the response is signed with the
// endorsing identity while the party is looked up by its P2P identity, this binding is
// what lets that check succeed.
//
// The bind call is deliberately Bind(longTerm: endorsingIdentity, ephemeral: p2pIdentity),
// not the other way around. Loading any bccsp MSP (including the endorsingIdentity's own
// fabric.default.msps entry, loaded a moment earlier during fsc.Start()) auto-binds it, via
// msp/service.go's AddMSP, as an ephemeral of *this node's own* default identity. The
// binding store's PutBindings does INSERT ... ON CONFLICT DO NOTHING keyed by the ephemeral's
// hash, so calling Bind(p2pIdentity, endorsingIdentity) here would try to re-key that
// already-claimed row and silently no-op (Bind returns nil either way, which is why this
// direction fails without ever logging an error). Binding the other way instead adds a new
// row for the previously-unclaimed p2pIdentity ephemeral; PutBindings resolves
// endorsingIdentity's already-registered canonical long-term first (GetLongTerm) and reuses
// it, so both endorsingIdentity and p2pIdentity end up mapped to the same long-term id and
// IsBoundTo(endorsingIdentity, p2pIdentity) reports true.
//
// mspLabel/p2pName pairs that aren't configured (e.g. this platform doesn't use
// fsc_endorsement, or this node isn't a party that verifies it) are skipped, logged, and
// otherwise ignored, so this is safe to call unconditionally from every node's main.
func BindEndorsingIdentities(fsc *node.Node, network string, mspLabelToP2PName map[string]string) {
	if len(mspLabelToP2PName) == 0 {
		return
	}

	fns, err := fabric.GetFabricNetworkService(fsc, network)
	if err != nil {
		log.Printf("skip binding endorsing identities: fabric network service [%s] not found: %v", network, err)
		return
	}
	idProvider, err := id.GetProvider(fsc)
	if err != nil {
		log.Printf("skip binding endorsing identities: failed getting identity provider: %v", err)
		return
	}

	for mspLabel, p2pName := range mspLabelToP2PName {
		endorsingIdentity, err := fns.LocalMembership().GetIdentityByID(mspLabel)
		if err != nil {
			log.Printf("skip binding endorsing identity [%s]: %v", mspLabel, err)
			continue
		}
		p2pIdentity := idProvider.Identity(p2pName)
		if p2pIdentity.IsNone() {
			log.Printf("skip binding endorsing identity [%s]: P2P identity [%s] not found", mspLabel, p2pName)
			continue
		}
		if err := endpoint.GetService(fsc).Bind(context.Background(), endorsingIdentity, p2pIdentity); err != nil {
			log.Printf("failed binding endorsing identity [%s] to [%s]: %v", mspLabel, p2pName, err)
		}
	}
}

// WithAnyCORS adds permissive CORS headers to all responses
func WithAnyCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Allow all origins
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		// Handle preflight requests
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
