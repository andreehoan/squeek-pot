// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

/// @title PinnedVRFConsumerV2Plus
/// @notice A minimal Chainlink VRF 2.5 consumer whose coordinator is IMMUTABLE, and which
///         deliberately does NOT expose `setCoordinator`.
///
/// @dev WHY THIS REPLACES Chainlink's `VRFConsumerBaseV2Plus`:
///      The stock base stores the coordinator in a MUTABLE `s_vrfCoordinator` and exposes an
///      inherited `onlyOwnerOrCoordinator setCoordinator(address)`. Even when the consumer
///      re-checks an immutable pin inside `fulfillRandomWords`, the base's `rawFulfillRandomWords`
///      gate runs FIRST:
///          if (msg.sender != address(s_vrfCoordinator)) revert OnlyCoordinatorCanFulfill(...);
///      So an owner who swaps `s_vrfCoordinator` AFTER a request makes the REAL coordinator's
///      callback revert at that gate. The VRF coordinator deletes the request commitment and
///      records the callback failure WITHOUT reverting, so the draw is consumed-and-lost; the
///      owner then recovers the stuck draw and re-rolls until a chosen winner appears — i.e. the
///      owner can CENSOR unfavorable VRF outcomes. (Found in a red-team pass; see AUDIT.md.)
///
///      Pinning the coordinator immutably and removing `setCoordinator` closes that vector: no
///      owner action can change the address `rawFulfillRandomWords` authenticates against, so a
///      legitimate callback can never be made to fail. Coordinator migration = redeploy (the
///      intended, documented trade-off).
abstract contract PinnedVRFConsumerV2Plus is ConfirmedOwner {
    error OnlyCoordinatorCanFulfill(address have, address want);
    error ZeroCoordinator();

    /// @notice The VRF 2.5 coordinator, pinned at deploy and NEVER changeable.
    IVRFCoordinatorV2Plus public immutable vrfCoordinator;

    constructor(address _vrfCoordinator) ConfirmedOwner(msg.sender) {
        if (_vrfCoordinator == address(0)) revert ZeroCoordinator();
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
    }

    /// @notice Consumer-implemented randomness handler (called only via `rawFulfillRandomWords`).
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;

    /// @notice Coordinator entrypoint, authenticated against the IMMUTABLE coordinator — so no
    ///         owner action can make a genuine callback fail this gate.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(vrfCoordinator));
        }
        fulfillRandomWords(requestId, randomWords);
    }
}
