# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FROM golang:1.27.1-bookworm AS builder

ENV GOCACHE=/go-cache \
    GOMODCACHE=/gomod-cache \
    CGO_ENABLED=0

# Change the hash to checkout a different commit / version tag. It should be the same as in app/go.mod.
RUN git clone https://github.com/LFDT-Panurus/panurus.git && \
    cd panurus && \
    git checkout c90448b4c2635862fb5b9b41b8be2df7934ccb38

RUN --mount=type=cache,target=/gomod-cache \
    --mount=type=cache,target=/go-cache \
    cd panurus; go build -buildvcs=false -o /tcc token/services/network/fabric/tcc/main/main.go

# Final image
FROM scratch
ENV CHAINCODE_TLS=false
COPY --from=builder /tcc /usr/bin/tcc
EXPOSE 9999

ENV PUBLIC_PARAMS_FILE_PATH=/zkatdlognoghv1_pp.json
ADD zkatdlognoghv1_pp.json /zkatdlognoghv1_pp.json

CMD ["tcc"]
