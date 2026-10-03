/*
Copyright IBM Corp. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

package routes

import (
	"context"
	"errors"

	"github.com/LFDT-Panurus/panurus/token"
	"github.com/hyperledger/fabric-samples/token-sdk/issuer/service"
)

//go:generate go tool github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen --config=./oapi-server.yaml ../../swagger.yaml

type Server struct {
	fsc *service.FabricSmartClient
}

func NewServer(fsc *service.FabricSmartClient) Server {
	return Server{fsc: fsc}
}

// Issue tokens of any kind to an account
// (POST /issuer/issue)
func (s Server) Issue(ctx context.Context, request IssueRequestObject) (IssueResponseObject, error) {
	if request.Body == nil {
		return nil, errors.New("no body")
	}
	var message string
	if request.Body.Message != nil {
		message = *request.Body.Message
	}
	res, err := s.fsc.Issue(ctx,
		request.Body.Amount.Code,
		request.Body.Amount.Value,
		request.Body.Counterparty.Account,
		request.Body.Counterparty.Node,
		message,
		toTMSID(request.Body.TmsId),
	)
	if err != nil {
		return nil, err
	}
	return Issue200JSONResponse{IssueSuccessJSONResponse{
		Message: "ok",
		Payload: res,
	}}, err
}

// toTMSID converts the optional TMS identifier of a request. A nil result selects the node's default TMS.
func toTMSID(id *TMSID) *token.TMSID {
	if id == nil {
		return nil
	}
	return &token.TMSID{Network: id.Network, Channel: id.Channel, Namespace: id.Namespace}
}

// Returns 200 if the service is healthy
// (GET /healthz)
func (s Server) Healthz(ctx context.Context, request HealthzRequestObject) (HealthzResponseObject, error) {
	return Healthz200JSONResponse{HealthSuccessJSONResponse{Message: "ok"}}, nil
}

// Returns 200 if the service is ready to accept calls
// (GET /readyz)
func (s Server) Readyz(ctx context.Context, request ReadyzRequestObject) (ReadyzResponseObject, error) {
	return Readyz200JSONResponse{HealthSuccessJSONResponse{Message: "ok"}}, nil
}
