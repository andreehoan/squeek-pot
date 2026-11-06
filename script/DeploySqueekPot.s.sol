// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SqueekPot} from "../src/SqueekPot.sol";

/// @notice Deploys SqueekPot. All params come from env so nothing is hardcoded.
/// @dev Usage (Sepolia):
///   export SQK=0xd78a3956cf63164d1fa1c622ad3c66623162fa1e        # staged-launch-1 SQK
///   export VRF_COORDINATOR=0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B
///   export VRF_KEYHASH=0x...        # Sepolia gas lane (see README)
///   export VRF_SUB_ID=...           # your funded VRF 2.5 subscription id
///   # optional: VRF_CONFIRMATIONS(3) VRF_CALLBACK_GAS(200000) VRF_PAY_NATIVE(false)
///   #           DRAW_INTERVAL(86400) FIRST_DRAW_DELAY(86400)
///   forge script script/DeploySqueekPot.s.sol --rpc-url $SEPOLIA_RPC --broadcast --account <acct>
///   # then add the printed address as a consumer on your VRF subscription.
contract DeploySqueekPot is Script {
    function run() external returns (SqueekPot pot) {
        address sqk = vm.envAddress("SQK");
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        bytes32 keyHash = vm.envBytes32("VRF_KEYHASH");
        uint256 subId = vm.envUint("VRF_SUB_ID");
        uint16 confs = uint16(vm.envOr("VRF_CONFIRMATIONS", uint256(3)));
        uint32 cbGas = uint32(vm.envOr("VRF_CALLBACK_GAS", uint256(200_000)));
        bool payNative = vm.envOr("VRF_PAY_NATIVE", false);
        uint256 interval = vm.envOr("DRAW_INTERVAL", uint256(1 days));
        uint256 firstDelay = vm.envOr("FIRST_DRAW_DELAY", uint256(1 days));
        address boostNft = vm.envAddress("BOOST_NFT"); // Squeek Genesis NFT (holder odds boost)

        vm.startBroadcast();
        pot = new SqueekPot(sqk, coordinator, keyHash, subId, confs, cbGas, payNative, interval, firstDelay, boostNft);
        vm.stopBroadcast();

        console2.log("SqueekPot deployed:", address(pot));
        console2.log("-> Add it as a consumer on VRF subscription:", subId);
    }
}
