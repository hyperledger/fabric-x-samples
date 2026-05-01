# Fabric-X Samples

## Overview

Fabric-X Samples is the official home repository for sample applications built on top of Hyperledger Fabric-X. This repository provides reference implementations, tutorials, and example projects that demonstrate how to develop and deploy applications using the Fabric-X framework.

## Purpose

This repository serves as a comprehensive resource for developers looking to:

- Learn Fabric-X development through practical examples
- Understand best practices for building Fabric-X applications
- Explore different use cases and implementation patterns
- Get started quickly with pre-configured sample projects

## Current samples

### [Tokens Sample](https://github.com/hyperledger/fabric-x-samples/tree/main/tokens)

A complete token management application demonstrating:

- Token issuance and transfer workflows
- Multi-party endorsement patterns
- Integration with Fabric Smart Client (FSC)
- REST API implementations for issuers, owners, and endorsers
- Docker Compose and Ansible deployment configurations
- Support for both Fabric 3.x and Fabric-X environments

### [SDK Endorser](https://github.com/hyperledger/fabric-x-samples/tree/main/endorser)

A minimal example of a custom endorser service built with the Fabric-X SDK. Unlike classic
chaincode, an endorser runs as a standalone gRPC service outside the peer. The sample shows how to
implement the single `Executor` interface, wire it into the endorser server, and submit transactions
through an included client CLI against a local test network.

## Coming soon

- [ ] [EVM Integration](https://github.com/hyperledger/fabric-x-evm) example
- [ ] Base CRUD application with FSC [#1](https://github.com/hyperledger/fabric-x-samples/issues/1)
