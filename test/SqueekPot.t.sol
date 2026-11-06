// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekPot} from "../src/SqueekPot.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockBadERC721} from "./mocks/MockBadERC721.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract SqueekPotTest is Test {
    SqueekPot internal pot;
    MockERC20 internal sqk;
    VRFCoordinatorV2_5Mock internal vrf;
    MockERC721 internal genesisNft;
    uint256 internal subId;

    bytes32 internal constant KEY_HASH = bytes32(uint256(0x1234));
    uint256 internal constant INTERVAL = 1 days;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        vrf = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        subId = vrf.createSubscription();
        vrf.fundSubscription(subId, 1000 ether);

        sqk = new MockERC20();
        genesisNft = new MockERC721();
        pot = new SqueekPot(
            address(sqk),
            address(vrf),
            KEY_HASH,
            subId,
            3, // confirmations
            500_000, // callback gas limit
            false, // pay in LINK (sub funded above)
            INTERVAL,
            INTERVAL, // first draw delay
            address(genesisNft) // Squeek Genesis NFT (holder boost)
        );
        vrf.addConsumer(subId, address(pot));
    }

    // --------------------------------------------------------------------- //
    //                               Helpers                                 //
    // --------------------------------------------------------------------- //

    function _give(address who, uint256 amount) internal {
        sqk.mint(who, amount);
        vm.prank(who);
        sqk.approve(address(pot), type(uint256).max);
    }

    function _deposit(address who, uint256 amount) internal {
        _give(who, amount);
        vm.prank(who);
        pot.deposit(amount);
    }

    function _seed(uint256 amount) internal {
        sqk.mint(address(this), amount);
        sqk.approve(address(pot), amount);
        pot.fundPrize(amount);
    }

    function _giveNft(address who) internal {
        genesisNft.mint(who);
    }

    function _freshPotWithBoostNft(address nft) internal returns (SqueekPot p) {
        p = new SqueekPot(
            address(sqk), address(vrf), KEY_HASH, subId, 3, 500_000, false, INTERVAL, INTERVAL, nft
        );
        vrf.addConsumer(subId, address(p));
    }

    /// @dev Runs a full draw forcing a specific random word (deterministic winner).
    function _drawWithWord(uint256 word) internal returns (address winner) {
        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw();
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);
        pot.settleDraw();
        return pot.lastWinner();
    }

    // --------------------------------------------------------------------- //
    //                          Deposit / Withdraw                           //
    // --------------------------------------------------------------------- //

    function test_DepositTracksBalanceAndParticipant() public {
        _deposit(alice, 100e18);
        assertEq(pot.deposits(alice), 100e18);
        assertEq(pot.totalDeposits(), 100e18);
        assertEq(pot.participantCount(), 1);
        assertEq(sqk.balanceOf(address(pot)), 100e18);
    }

    function test_WithdrawFullRemovesParticipant() public {
        _deposit(alice, 100e18);
        vm.prank(alice);
        pot.withdraw(100e18);
        assertEq(pot.deposits(alice), 0);
        assertEq(pot.totalDeposits(), 0);
        assertEq(pot.participantCount(), 0);
        assertEq(sqk.balanceOf(alice), 100e18);
    }

    function test_WithdrawPartialKeepsParticipant() public {
        _deposit(alice, 100e18);
        vm.prank(alice);
        pot.withdraw(40e18);
        assertEq(pot.deposits(alice), 60e18);
        assertEq(pot.participantCount(), 1);
    }

    function test_PartialWithdrawBelowMinReverts() public {
        _deposit(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert(SqueekPot.BelowMinimum.selector);
        pot.withdraw(99.5e18); // would leave 0.5 SQK < MIN_DEPOSIT
    }

    function test_DepositBelowMinReverts() public {
        _give(alice, 0.5e18);
        vm.prank(alice);
        vm.expectRevert(SqueekPot.BelowMinimum.selector);
        pot.deposit(0.5e18);
    }

    function test_WithdrawMoreThanBalanceReverts() public {
        _deposit(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert(SqueekPot.InsufficientBalance.selector);
        pot.withdraw(101e18);
    }

    // --------------------------------------------------------------------- //
    //                              Prize funding                            //
    // --------------------------------------------------------------------- //

    function test_FundPrizeAccrues() public {
        _seed(500e18);
        assertEq(pot.prizeReserve(), 500e18);
    }

    function test_SyncPrizeSweepsDirectTransfer() public {
        _deposit(alice, 100e18);
        sqk.mint(address(pot), 7e18); // someone sends SQK directly
        pot.syncPrize();
        assertEq(pot.prizeReserve(), 7e18);
        assertEq(pot.totalDeposits(), 100e18); // deposits untouched
    }

    // --------------------------------------------------------------------- //
    //                           Draw request gating                         //
    // --------------------------------------------------------------------- //

    function test_RequestDrawTooEarlyReverts() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.expectRevert(SqueekPot.TooEarly.selector);
        pot.requestDraw();
    }

    function test_RequestDrawNoPlayersReverts() public {
        _seed(50e18);
        vm.warp(pot.nextDrawTime());
        vm.expectRevert(SqueekPot.NoPlayers.selector);
        pot.requestDraw();
    }

    function test_RequestDrawNoPrizeReverts() public {
        _deposit(alice, 100e18);
        vm.warp(pot.nextDrawTime());
        vm.expectRevert(SqueekPot.NoPrize.selector);
        pot.requestDraw();
    }

    // --------------------------------------------------------------------- //
    //                            Full draw cycle                            //
    // --------------------------------------------------------------------- //

    function test_FullDrawCycleResetsState() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        uint256 t0 = pot.nextDrawTime();

        address winner = _drawWithWord(0);
        assertEq(winner, alice);
        assertEq(sqk.balanceOf(alice), 50e18); // prize paid
        assertEq(pot.prizeReserve(), 0);
        assertEq(pot.totalDeposits(), 100e18); // deposit untouched
        assertEq(pot.deposits(alice), 100e18);
        assertEq(uint8(pot.drawState()), uint8(SqueekPot.DrawState.Idle));
        assertEq(pot.roundId(), 1);
        assertEq(pot.nextDrawTime(), block.timestamp + INTERVAL);
        assertGt(pot.nextDrawTime(), t0);
        assertEq(pot.lastPrize(), 50e18);
        assertEq(pot.totalPaidOut(), 50e18);
    }

    function test_WeightedWinnerDeterministic() public {
        // participants order: [alice, bob]; alice 100, bob 300, total 400.
        _deposit(alice, 100e18);
        _deposit(bob, 300e18);
        _seed(10e18);

        // target = word % 400e18. 50e18 < 100e18 -> alice.
        address w1 = _drawWithWord(50e18);
        assertEq(w1, alice);

        // next round: re-seed, target = 200e18 -> in [100e18,400e18) -> bob.
        _seed(10e18);
        address w2 = _drawWithWord(200e18);
        assertEq(w2, bob);
    }

    function test_NoLoss_AllCanWithdrawAfterDraw() public {
        _deposit(alice, 100e18);
        _deposit(bob, 300e18);
        _seed(40e18);

        _drawWithWord(50e18); // alice wins the prize

        // Both the winner and the loser can still pull 100% of principal.
        vm.prank(alice);
        pot.withdraw(100e18);
        vm.prank(bob);
        pot.withdraw(300e18);

        assertEq(pot.totalDeposits(), 0);
        assertEq(sqk.balanceOf(alice), 100e18 + 40e18); // principal + prize
        assertEq(sqk.balanceOf(bob), 300e18); // principal, no loss
    }

    function test_SnapshotWinnerPaidEvenAfterWithdraw() public {
        _deposit(alice, 100e18);
        _seed(50e18);

        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw(); // snapshot locks [alice]

        // Alice pulls her principal after the request — still eligible via snapshot.
        vm.prank(alice);
        pot.withdraw(100e18);
        assertEq(pot.totalDeposits(), 0);

        uint256[] memory words = new uint256[](1);
        words[0] = 12345;
        vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);
        pot.settleDraw();

        // She wins off the frozen snapshot; walks away with principal + prize.
        assertEq(pot.lastWinner(), alice);
        assertEq(pot.prizeReserve(), 0);
        assertEq(sqk.balanceOf(alice), 100e18 + 50e18);
        assertEq(pot.roundId(), 1);
    }

    // --- P1 regression: winner cannot be changed after the random word is public ---

    function test_WinnerImmuneToPostReadyReorder() public {
        _deposit(alice, 100e18);
        _deposit(bob, 100e18);
        _deposit(carol, 100e18);
        _seed(30e18);

        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw(); // freezes [alice,bob,carol] cum[100,200,300]

        uint256[] memory words = new uint256[](1);
        words[0] = 250e18; // 250 in [200,300) -> carol in the snapshot
        vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);

        // Bob (seeing the word) reorders the LIVE list via withdraw+redeposit to try
        // to move the 250 slot onto himself.
        vm.prank(bob);
        pot.withdraw(100e18);
        _give(bob, 100e18);
        vm.prank(bob);
        pot.deposit(100e18);

        pot.settleDraw();
        assertEq(pot.lastWinner(), carol); // snapshot wins; manipulation failed
    }

    function test_WinnerImmuneToPostReadyDeposit() public {
        _deposit(alice, 100e18);
        _deposit(bob, 100e18);
        _seed(10e18);

        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw(); // snapshot total 200, cum [100,200]

        uint256[] memory words = new uint256[](1);
        words[0] = 150e18; // 150 in [100,200) -> bob
        vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);

        _deposit(carol, 100e18); // late entry changes LIVE total to 300

        pot.settleDraw();
        assertEq(pot.lastWinner(), bob); // snapshot total 200 used; carol ignored
    }

    function test_CoordinatorSwapBlocksDraw() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.warp(pot.nextDrawTime());

        // owner moves the base coordinator; pinned i_coordinator no longer matches
        assertEq(pot.i_coordinator(), address(vrf));
        pot.setCoordinator(address(0xBEEF));
        vm.expectRevert(SqueekPot.CoordinatorChanged.selector);
        pot.requestDraw();
    }

    function test_FundingAfterRequestRollsToNextRound() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw();

        _seed(25e18); // extra funding after the snapshot

        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);
        pot.settleDraw();

        assertEq(pot.lastPrize(), 50e18); // only the snapshotted amount was paid
        assertEq(pot.prizeReserve(), 25e18); // extra remains for next round
    }

    // --------------------------------------------------------------------- //
    //                               Pause                                   //
    // --------------------------------------------------------------------- //

    function test_PauseBlocksDepositButNotWithdraw() public {
        _deposit(alice, 100e18);
        pot.pause();

        _give(bob, 100e18);
        vm.prank(bob);
        vm.expectRevert(); // Pausable: paused
        pot.deposit(100e18);

        // withdraw still works while paused (no-loss guarantee)
        vm.prank(alice);
        pot.withdraw(100e18);
        assertEq(sqk.balanceOf(alice), 100e18);
    }

    // --------------------------------------------------------------------- //
    //                           Access control                             //
    // --------------------------------------------------------------------- //

    function test_SetVrfConfigOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pot.setVrfConfig(bytes32(uint256(9)), subId, 5, 300000, true);

        // owner succeeds
        pot.setVrfConfig(bytes32(uint256(9)), subId, 5, 300000, true);
        assertEq(pot.requestConfirmations(), 5);
    }

    function test_PauseOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pot.pause();
    }

    function test_OnlyCoordinatorCanFulfill() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw();

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.prank(alice);
        vm.expectRevert(); // OnlyCoordinatorCanFulfill
        pot.rawFulfillRandomWords(reqId, words);
    }

    function test_CancelStuckDraw() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.warp(pot.nextDrawTime());
        pot.requestDraw();

        // too soon
        vm.expectRevert(SqueekPot.NotStuck.selector);
        pot.cancelStuckDraw();

        // after timeout, owner can reset without touching the prize
        vm.warp(block.timestamp + pot.DRAW_TIMEOUT() + 1);
        pot.cancelStuckDraw();
        assertEq(uint8(pot.drawState()), uint8(SqueekPot.DrawState.Idle));
        assertEq(pot.prizeReserve(), 50e18);
        assertEq(pot.roundId(), 1);
    }

    function test_CannotRequestWhileBusy() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.warp(pot.nextDrawTime());
        pot.requestDraw();
        vm.expectRevert(SqueekPot.DrawBusy.selector);
        pot.requestDraw();
    }

    // --------------------------------------------------------------------- //
    //                      Hardening regressions (Round 3)                  //
    // --------------------------------------------------------------------- //

    /// Round-3 codex fix: a Ready draw (determined, public winner) is NOT recoverable —
    /// neither the owner nor the permissionless path may censor a known outcome, even
    /// long past both timeouts. It must settle, paying the determined winner.
    function test_ReadyDrawNotRecoverableMustSettle() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw();
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);
        assertEq(uint8(pot.drawState()), uint8(SqueekPot.DrawState.Ready));

        // Even far past BOTH timeouts, a Ready draw cannot be cancelled/censored.
        vm.warp(block.timestamp + pot.STUCK_FALLBACK_TIMEOUT() + 1);
        vm.expectRevert(SqueekPot.NotStuck.selector);
        pot.cancelStuckDraw();
        vm.prank(bob);
        vm.expectRevert(SqueekPot.NotStuck.selector);
        pot.forceRecoverStuckDraw();

        // It stays settleable → the determined winner is paid.
        pot.settleDraw();
        assertEq(pot.lastWinner(), alice);
        assertEq(pot.lastPrize(), 50e18);
    }

    /// P3 fix: permissionless fallback recovers a stuck draw after the longer grace,
    /// even with the owner key lost. Reverts before the fallback window elapses.
    function test_ForceRecoverPermissionless() public {
        _deposit(alice, 100e18);
        _seed(50e18);
        vm.warp(pot.nextDrawTime());
        pot.requestDraw(); // Requested; never fulfilled

        // owner's DRAW_TIMEOUT passed, but the public fallback window has not
        vm.warp(block.timestamp + pot.DRAW_TIMEOUT() + 1);
        vm.prank(bob);
        vm.expectRevert(SqueekPot.NotStuck.selector);
        pot.forceRecoverStuckDraw();

        // past the fallback window → anyone (bob, not owner) can recover
        vm.warp(block.timestamp + pot.STUCK_FALLBACK_TIMEOUT());
        vm.prank(bob);
        pot.forceRecoverStuckDraw();
        assertEq(uint8(pot.drawState()), uint8(SqueekPot.DrawState.Idle));
        assertEq(pot.prizeReserve(), 50e18);
        assertEq(pot.roundId(), 1);
    }

    function test_ForceRecoverRevertsWhenIdle() public {
        vm.expectRevert(SqueekPot.NotStuck.selector);
        pot.forceRecoverStuckDraw();
    }

    /// P1 fix: the packed-snapshot uint96 cap — deposits are rejected past MAX_TOTAL.
    function test_DepositOverMaxTotalReverts() public {
        uint256 cap = pot.MAX_TOTAL();
        _give(alice, cap);
        vm.prank(alice);
        pot.deposit(cap); // exactly the cap is allowed
        assertEq(pot.totalDeposits(), cap);

        _give(bob, 1e18);
        vm.prank(bob);
        vm.expectRevert(SqueekPot.TotalCapExceeded.selector);
        pot.deposit(1e18);
    }

    /// P1 fix: packed snapshot still selects the correct weighted winner (unpack check).
    function test_PackedWeightedSelection() public {
        _deposit(alice, 100e18); // snapshot cum: alice [0,100)
        _deposit(bob, 300e18); //   bob   [100,400)
        _seed(10e18);
        // target = 50 < 100 → the first packed entry (alice) must be unpacked, not bob.
        assertEq(_drawWithWord(50e18), alice);
    }

    // --------------------------------------------------------------------- //
    //                       Genesis NFT odds boost                          //
    // --------------------------------------------------------------------- //

    function test_BoostDefaultsTo20Pct() public view {
        assertEq(pot.boostBps(), 2000);
    }

    /// A Genesis-NFT holder's weight is lifted +20%, which can flip the winner at a boundary that
    /// WITHOUT the boost would land on the other player.
    function test_BoostLiftsHolderWeight() public {
        _giveNft(alice); // alice holds a Genesis NFT → weight 100 → 120
        _deposit(alice, 100e18); // boosted cum [0,120)
        _deposit(bob, 100e18); // cum [120,220); total 220
        _seed(10e18);
        // target 115 < 120 → alice. (Unboosted: total 200, 115 ≥ 100 → bob.) The boost decides it.
        assertEq(_drawWithWord(115e18), alice);
    }

    /// A non-holder is not boosted; only bob (holder) gets the lift.
    function test_NonHolderNotBoosted() public {
        _deposit(alice, 100e18); // no NFT → cum [0,100)
        _giveNft(bob);
        _deposit(bob, 100e18); // boosted → cum [100,220); total 220
        _seed(10e18);
        assertEq(_drawWithWord(150e18), bob);
    }

    function test_HoldsBoostNftView() public {
        assertFalse(pot.holdsBoostNft(alice));
        _giveNft(alice);
        assertTrue(pot.holdsBoostNft(alice));
    }

    /// A misbehaving boost NFT (reverting / oversized-return / gas-burning balanceOf) must never
    /// brick a draw — it just yields no boost. Exercises the gas-bounded, 32-byte-capped read.
    function test_BadBoostNftCannotBrickDraw() public {
        for (uint8 m = 1; m <= 3; ++m) {
            MockBadERC721 bad = new MockBadERC721(m);
            SqueekPot p = _freshPotWithBoostNft(address(bad));
            address u = makeAddr(string(abi.encodePacked("bad", m)));
            sqk.mint(u, 100e18);
            vm.prank(u);
            sqk.approve(address(p), type(uint256).max);
            vm.prank(u);
            p.deposit(100e18);
            sqk.mint(address(this), 10e18);
            sqk.approve(address(p), 10e18);
            p.fundPrize(10e18);
            vm.warp(p.nextDrawTime());
            p.requestDraw(); // must NOT revert despite the bad boostNft
            assertEq(uint8(p.drawState()), uint8(SqueekPot.DrawState.Requested));
            assertFalse(p.holdsBoostNft(u)); // bad NFT read → treated as no-boost
        }
    }
}
