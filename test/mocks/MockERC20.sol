// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal mintable ERC20 standing in for SQK in tests (18 decimals).
contract MockERC20 is ERC20 {
    constructor() ERC20("Squeek", "SQK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
