// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekPot} from "../src/SqueekPot.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/// @dev Drives random deposit/withdraw/fund/draw sequences against the pot.
contract Handler is Test {
    SqueekPot public pot;
    MockERC20 public sqk;
    VRFCoordinatorV2_5Mock public vrf;
    address[4] public actors;

    constructor(SqueekPot _pot, MockERC20 _sqk, VRFCoordinatorV2_5Mock _vrf) {
        pot = _pot;
        sqk = _sqk;
        vrf = _vrf;
        actors[0] = makeAddr("a0");
        actors[1] = makeAddr("a1");
        actors[2] = makeAddr("a2");
        actors[3] = makeAddr("a3");
        for (uint256 i = 0; i < 4; ++i) {
            sqk.mint(actors[i], 1_000_000e18);
            vm.prank(actors[i]);
            sqk.approve(address(pot), type(uint256).max);
        }
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function deposit(uint256 seed, uint256 amount) external {
        address a = actors[seed % 4];
        amount = bound(amount, 1e18, 100_000e18);
        vm.prank(a);
        try pot.deposit(amount) {} catch {}
    }

    function withdraw(uint256 seed, uint256 amount) external {
        address a = actors[seed % 4];
        uint256 bal = pot.deposits(a);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        // avoid the dust-floor revert: if the remainder would be below MIN, exit fully
        if (bal - amount != 0 && bal - amount < pot.MIN_DEPOSIT()) amount = bal;
        vm.prank(a);
        try pot.withdraw(amount) {} catch {}
    }

    function fundPrize(uint256 amount) external {
        amount = bound(amount, 1e18, 10_000e18);
        sqk.mint(address(this), amount);
        sqk.approve(address(pot), amount);
        try pot.fundPrize(amount) {} catch {}
    }

    function strayTransfer(uint256 amount, bool sync) external {
        amount = bound(amount, 1, 5_000e18);
        sqk.mint(address(pot), amount); // simulate a raw ERC20 transfer into the pot
        if (sync) try pot.syncPrize() {} catch {}
    }

    function runDraw(uint256 word) external {
        vm.warp(block.timestamp + 1 days + 1);
        if (!pot.canRequestDraw()) return;
        try pot.requestDraw() returns (uint256 reqId) {
            uint256[] memory words = new uint256[](1);
            words[0] = word;
            vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);
            pot.settleDraw();
        } catch {}
    }
}

contract SqueekPotInvariantTest is Test {
    SqueekPot internal pot;
    MockERC20 internal sqk;
    VRFCoordinatorV2_5Mock internal vrf;
    Handler internal handler;

    function setUp() public {
        vrf = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        uint256 subId = vrf.createSubscription();
        vrf.fundSubscription(subId, 100_000 ether);
        sqk = new MockERC20();
        MockERC721 nft = new MockERC721();
        pot = new SqueekPot(address(sqk), address(vrf), bytes32(uint256(1)), subId, 3, 500_000, false, 1 days, 1 days, address(nft));
        vrf.addConsumer(subId, address(pot));

        handler = new Handler(pot, sqk, vrf);
        // give half the actors a Genesis NFT so the boosted snapshot path is fuzzed too
        nft.mint(handler.actorAt(0));
        nft.mint(handler.actorAt(2));
        targetContract(address(handler));
    }

    /// The core no-loss guarantee: the pot always holds at least everyone's principal.
    function invariant_BalanceCoversDeposits() public view {
        assertGe(sqk.balanceOf(address(pot)), pot.totalDeposits());
    }

    /// Deposit accounting is exact: per-actor balances sum to totalDeposits.
    function invariant_DepositAccountingExact() public view {
        uint256 sum;
        for (uint256 i = 0; i < 4; ++i) {
            sum += pot.deposits(handler.actorAt(i));
        }
        assertEq(sum, pot.totalDeposits());
    }

    /// No leakage: every token held covers deposits + prize. Raw transfers into the
    /// pot create a transient surplus until syncPrize folds it into the prize, so this
    /// is a >= bound (never <, which would mean principal or prize was lost).
    function invariant_NoLeak() public view {
        assertGe(sqk.balanceOf(address(pot)), pot.totalDeposits() + pot.prizeReserve());
    }
}
