// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @dev Minimal mintable ERC-721 standing in for the Squeek Genesis NFT in tests.
contract MockERC721 is ERC721 {
    uint256 public nextId;

    constructor() ERC721("MockSqueek", "mSQUEEK") {}

    function mint(address to) external returns (uint256 id) {
        id = ++nextId;
        _mint(to, id);
    }
}
