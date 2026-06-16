// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Token — a minimal, standard ERC-20.
/// @notice The entire initial supply is minted to the deployer. `name`,
/// `symbol`, and `initialSupply` are supplied to the constructor, so the same
/// bytecode can be reused for any token (see `make deploy NAME=... SYMBOL=...`).
/// @dev `initialSupply` is the raw amount in the token's smallest unit. ERC-20
/// uses 18 decimals by default, so one whole token is `1 * 10**18`.
contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol)
    {
        _mint(msg.sender, initialSupply);
    }
}
