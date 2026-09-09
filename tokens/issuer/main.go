/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path"
	"syscall"
	"time"

	viewregistry "github.com/hyperledger-labs/fabric-smart-client/platform/view/services/view"
	"github.com/hyperledger/fabric-samples/token-sdk/common"
	"github.com/hyperledger/fabric-samples/token-sdk/common/views"
	"github.com/hyperledger/fabric-samples/token-sdk/issuer/routes"
	"github.com/hyperledger/fabric-samples/token-sdk/issuer/service"
)

func main() {
	// Flags
	cwd, _ := os.Getwd()
	pth := flag.String("conf", cwd, "the directory that contains the core.yaml configuration file")
	port := flag.String("port", "9000", "the API port for the application")
	flag.Parse()

	// Fabric smart client
	fsc, err := common.StartFSC(*pth, path.Join(*pth, "data"))
	if err != nil {
		log.Fatal(err)
	}

	// Let FSC-native endorsement collection (fabric3 platform) recognize a response signed
	// with an endorser's endorsing identity as coming from that endorser's P2P party.
	common.BindEndorsingIdentities(fsc, "default", map[string]string{
		"endorser1-endorsing": "endorser1",
		"endorser2-endorsing": "endorser2",
	})

	// Register views and responders (communication with other FSC nodes)
	reg := viewregistry.GetRegistry(fsc)
	reg.RegisterFactory("issue", &views.IssueCashViewFactory{})
	reg.RegisterResponder(&views.IssuerRedeemAcceptView{}, "github.com/hyperledger/fabric-samples/token-sdk/owner/service/RedeemView")

	// Simple web server
	sh := routes.NewStrictHandler(routes.NewServer(service.NewFSC(fsc)), []routes.StrictMiddlewareFunc{})
	h := common.WithAnyCORS(routes.HandlerFromMux(sh, http.NewServeMux()))
	s := &http.Server{
		Handler: h,
		Addr:    net.JoinHostPort("0.0.0.0", *port),
	}
	serverErr := make(chan error, 1)
	go func() {
		if err := s.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			serverErr <- err
		}
	}()

	// Stop
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	select {
	case <-stop:
	case err := <-serverErr:
		log.Printf("server error: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.TODO(), time.Second*10)
	defer cancel()
	s.Shutdown(ctx)
	fsc.Stop()
}
