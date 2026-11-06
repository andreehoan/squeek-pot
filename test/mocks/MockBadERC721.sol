// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev A deliberately misbehaving "NFT" used to prove the boost read cannot brick a draw.
///      mode 1 = balanceOf reverts; 2 = returns an oversized returndata bomb; 3 = burns gas.
contract MockBadERC721 {
    uint8 public immutable mode;

    constructor(uint8 _mode) {
        mode = _mode;
    }

    function balanceOf(address) external view returns (uint256) {
        if (mode == 1) revert("bad");
        if (mode == 2) {
            assembly {
                return(0, 4096)
            } // 4KB returndata — rejected by the 32-byte gate
        }
        if (mode == 3) {
            uint256 x;
            for (uint256 i; i < 2_000_000; ++i) {
                x = x + i;
            } // burns far past the 30k stipend
            return x;
        }
        return 1; // would look like a holder, but modes 1-3 never reach here
    }
}
