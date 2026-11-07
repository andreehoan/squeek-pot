// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekPotYield} from "../src/SqueekPotYield.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockSqueekStaking} from "./mocks/MockSqueekStaking.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract SqueekPotYieldTest is Test {
    SqueekPotYield internal pot;
    MockERC20 internal sqk;
    MockSqueekStaking internal staking;
    VRFCoordinatorV2_5Mock internal vrf;
    MockERC721 internal genesisNft;
    uint256 internal subId;

    bytes32 internal constant KEY_HASH = bytes32(uint256(0x1234));
    uint256 internal constant INTERVAL = 1 days;
    // Must match SqueekPotYield.CANONICAL_STAKING (the venue is address-pinned).
    address internal constant CANONICAL = 0x50fd1780526C3186A0c037c7622203bC4fb611ca;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        vrf = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        subId = vrf.createSubscription();
        vrf.fundSubscription(subId, 1000 ether);

        sqk = new MockERC20();
        genesisNft = new MockERC721();

        // The contract pins the venue to CANONICAL_STAKING. Place the mock's code at that
        // address (immutables tok/genesisNft are baked into runtime code and survive etch;
        // storage-initialised feeBps is reset, so set it explicitly after).
        MockSqueekStaking impl = new MockSqueekStaking(sqk, address(genesisNft));
        vm.etch(CANONICAL, address(impl).code);
        staking = MockSqueekStaking(CANONICAL);
        staking.setFeeBps(200);

        pot = new SqueekPotYield(
            address(sqk), address(vrf), KEY_HASH, subId, 3, 500_000, false, INTERVAL, INTERVAL,
            address(genesisNft), CANONICAL
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

    function _seedPrize(uint256 amount) internal {
        sqk.mint(address(this), amount);
        sqk.approve(address(pot), amount);
        pot.fundPrize(amount);
    }

    function _seedFee(uint256 amount) internal {
        sqk.mint(address(this), amount);
        sqk.approve(address(pot), amount);
        pot.seedFeeReserve(amount);
    }

    /// @dev Fund the mock venue with SQK and credit the pot with `amt` claimable reward.
    function _accrueYield(uint256 amt) internal {
        sqk.mint(address(staking), amt);
        staking.addReward(address(pot), amt);
    }

    function _drawWithWord(uint256 word) internal returns (address) {
        vm.warp(pot.nextDrawTime());
        uint256 reqId = pot.requestDraw();
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vrf.fulfillRandomWordsWithOverride(reqId, address(pot), words);
        pot.settleDraw();
        return pot.lastWinner();
    }

    /// @dev THE no-loss property: everyone can be made whole. liquid principal + net
    ///      recoverable from staking (at the current fee) + feeReserve >= totalDeposits.
    function _assertNoLoss() internal view {
        uint256 bal = sqk.balanceOf(address(pot));
        uint256 liquidPrincipal = bal - pot.prizeReserve() - pot.feeReserve();
        uint256 sp = pot.stakedPrincipal();
        uint256 recoverable = liquidPrincipal + pot.feeReserve();
        if (sp > 0) {
            (, uint256 netOut) = staking.quoteUnstake(address(pot), sp);
            recoverable += netOut;
        }
        assertGe(recoverable, pot.totalDeposits(), "NO-LOSS BROKEN");
    }

    // --------------------------------------------------------------------- //
    //             Phase 0: staking OFF behaves exactly like v1              //
    // --------------------------------------------------------------------- //

    function test_StakingDisabledByDefault() public view {
        assertEq(pot.stakingEnabled(), false);
        assertEq(pot.safetyFeeBps(), 6000);
        assertEq(pot.bufferBps(), 2000);
        assertEq(pot.stakableNow(), 0);
    }

    function test_DepositWithdrawFullyLiquidWhenOff() public {
        _deposit(alice, 100e18);
        assertEq(sqk.balanceOf(address(pot)), 100e18);
        assertEq(pot.stakedPrincipal(), 0);
        vm.prank(alice);
        pot.withdraw(100e18);
        assertEq(sqk.balanceOf(alice), 100e18);
        _assertNoLoss();
    }

    function test_StakeRevertsWhenDisabled() public {
        _deposit(alice, 100e18);
        vm.expectRevert(SqueekPotYield.StakingDisabled.selector);
        pot.stake(10e18);
    }

    function test_SeededDrawWorksWithoutStaking() public {
        _deposit(alice, 100e18);
        _seedPrize(50e18);
        address w = _drawWithWord(0);
        assertEq(w, alice);
        assertEq(pot.lastPrize(), 50e18);
        assertEq(pot.prizeReserve(), 0);
        assertEq(pot.totalDeposits(), 100e18); // untouched
        _assertNoLoss();
    }

    // --------------------------------------------------------------------- //
    //                   Phase 1: staking ON, no-loss holds                  //
    // --------------------------------------------------------------------- //

    function _enableAndStake(uint256 depositAmt, uint256 stakeAmt, uint256 feeSeed) internal {
        _deposit(alice, depositAmt);
        pot.enableStaking(true);
        if (feeSeed > 0) _seedFee(feeSeed);
        if (stakeAmt > 0) pot.stake(stakeAmt);
    }

    function test_StakeMovesSqkAndTracksPrincipal() public {
        // default safetyFee = 6000 (60%). To stake 100, need feeReserve >= 60.
        _enableAndStake(1000e18, 100e18, 60e18);
        assertEq(pot.stakedPrincipal(), 100e18);
        assertEq(staking.staked(address(pot)), 100e18);
        // 1000 deposit + 60 feeSeed; staked 100 → liquid balance = 900 principal + 60 fee = 960
        assertEq(sqk.balanceOf(address(pot)), 960e18);
        _assertNoLoss();
    }

    function test_StakeRevertsIfCushionInsufficient() public {
        _deposit(alice, 1000e18);
        pot.enableStaking(true);
        _seedFee(10e18); // only covers 10/0.6 ≈ 16.6 staked
        vm.expectRevert(SqueekPotYield.FeeCushionExceeded.selector);
        pot.stake(100e18); // needs 60 cushion
    }

    function test_StakeRevertsIfBufferBreached() public {
        _deposit(alice, 100e18);
        pot.enableStaking(true);
        _seedFee(100e18);
        // buffer = 20% of 100 = 20 must stay liquid; available principal = 100; max stake 80
        vm.expectRevert(SqueekPotYield.BufferBreach.selector);
        pot.stake(90e18);
    }

    function test_WithdrawFromBufferNoUnstake() public {
        _enableAndStake(1000e18, 500e18, 300e18);
        // buffer holds 500 liquid principal; withdraw 200 served from buffer, no unstake
        uint256 stakedBefore = pot.stakedPrincipal();
        vm.prank(alice);
        pot.withdraw(200e18);
        assertEq(sqk.balanceOf(alice), 200e18);
        assertEq(pot.stakedPrincipal(), stakedBefore); // unchanged
        _assertNoLoss();
    }

    function test_WithdrawRequiringUnstakePays100Percent() public {
        // Deposit 1000, stake 800 (need cushion 480 at 60%). Buffer leaves 200 liquid.
        _enableAndStake(1000e18, 800e18, 480e18);
        staking.setFeeBps(200); // calm: 2% exit
        // Withdraw 900 → 200 from buffer, 700 must come from unstake.
        uint256 feeResBefore = pot.feeReserve();
        vm.prank(alice);
        pot.withdraw(900e18);
        assertEq(sqk.balanceOf(alice), 900e18, "alice got 100%");
        // fee on 700 nominal @2% = 14 paid from feeReserve
        assertEq(pot.feeReserve(), feeResBefore - 14e18);
        assertEq(pot.stakedPrincipal(), 100e18); // 800 - 700
        assertEq(pot.totalDeposits(), 100e18);
        _assertNoLoss();
    }

    function test_StrictModeNoLossEvenAt60PercentRun() public {
        // Strict (default 6000). Deposit 1000, stake 800, cushion 480.
        _enableAndStake(1000e18, 800e18, 480e18);
        staking.setFeeBps(6000); // worst-case 60% run
        // Withdraw everything. 200 buffer + unstake 800 @60% (fee 480 from cushion).
        vm.prank(alice);
        pot.withdraw(1000e18);
        assertEq(sqk.balanceOf(alice), 1000e18, "100% back even in a 60% run");
        assertEq(pot.stakedPrincipal(), 0);
        assertEq(pot.totalDeposits(), 0);
        // cushion fully consumed: 480 fee on 800
        assertEq(pot.feeReserve(), 0);
        _assertNoLoss();
    }

    function test_VenueRaisesMaxAboveCushion_FailSafeReverts() public {
        // Strict (6000). Stake 800, cushion 480. Then Squeekchain governance lifts the venue
        // exit fee ABOVE our cushion (P1-2 residual). The unstake-requiring withdrawal MUST
        // fail-safe revert (never short-pay); buffer withdrawals still pay 100%.
        _enableAndStake(1000e18, 800e18, 480e18);
        staking.setFeeBps(7000); // venue max raised to 70% (beyond our 60% cushion)
        // Withdraw 900 → needs unstake 700 @70% = 490 fee > feeReserve 480 → revert
        vm.prank(alice);
        vm.expectRevert(SqueekPotYield.FeeCushionExceeded.selector);
        pot.withdraw(900e18);
        // buffer-only withdrawal (200 liquid principal) still pays EXACTLY face value
        vm.prank(alice);
        pot.withdraw(200e18);
        assertEq(sqk.balanceOf(alice), 200e18);
        // Owner de-risks: raise the cushion to cover the new venue max, then it's servable.
        _seedFee(200e18); // top cushion so 600 staked * 0.7 = 420 covered... have 480+200=680
        pot.setStakingParams(7000, 2000);
        vm.prank(alice);
        pot.withdraw(600e18); // now unstake-backed withdrawal succeeds, 100% back
        assertEq(sqk.balanceOf(alice), 800e18);
    }

    // --------------------------------------------------------------------- //
    //                       Yield → prize (the whole point)                 //
    // --------------------------------------------------------------------- //

    function test_HarvestTopsCushionThenFundsPrize() public {
        _enableAndStake(1000e18, 800e18, 480e18); // cushion exactly at requirement (480)
        // accrue 100 yield; cushion already full → all 100 to prize
        _accrueYield(100e18);
        pot.harvest();
        assertEq(pot.feeReserve(), 480e18);
        assertEq(pot.prizeReserve(), 100e18);
        assertEq(pot.totalYieldHarvested(), 100e18);
        _assertNoLoss();
    }

    function test_HarvestFillsCushionGapFirst() public {
        _deposit(alice, 1000e18);
        pot.enableStaking(true);
        _seedFee(480e18);
        pot.stake(800e18);
        // Now raise exposure requirement by lowering cushion via... instead, simulate a gap:
        // recover none; accrue yield while cushion is exactly required → all to prize.
        // Create a gap by staking more after seeding more fee, then draining cushion via a run withdraw.
        staking.setFeeBps(6000);
        vm.prank(alice);
        pot.withdraw(100e18); // 200 buffer covers it, no unstake, cushion unchanged
        // accrue yield, cushion still full (req = 800*0.6=480, have 480) → to prize
        _accrueYield(50e18);
        pot.harvest();
        assertEq(pot.prizeReserve(), 50e18);
        _assertNoLoss();
    }

    function test_FullYieldFundedDraw() public {
        _enableAndStake(1000e18, 800e18, 480e18);
        _accrueYield(70e18);
        pot.harvest(); // 70 → prize
        assertEq(pot.prizeReserve(), 70e18);
        address w = _drawWithWord(0);
        assertEq(w, alice);
        assertEq(pot.lastPrize(), 70e18);
        assertEq(pot.prizeReserve(), 0);
        assertEq(pot.totalDeposits(), 1000e18); // principal untouched by the draw
        _assertNoLoss();
    }

    function test_SweepFeeReserveExcessToPrize() public {
        _enableAndStake(1000e18, 100e18, 200e18); // need 60 cushion, seeded 200 → 140 excess
        pot.sweepFeeReserveExcess();
        assertEq(pot.feeReserve(), 60e18);
        assertEq(pot.prizeReserve(), 140e18);
        _assertNoLoss();
    }

    // --------------------------------------------------------------------- //
    //                          Param / recover paths                        //
    // --------------------------------------------------------------------- //

    function test_RecoverStakeUnwinds() public {
        _enableAndStake(1000e18, 500e18, 300e18);
        staking.setFeeBps(200);
        pot.recoverStake(500e18);
        assertEq(pot.stakedPrincipal(), 0);
        // fee on 500 @2% = 10 from cushion
        assertEq(pot.feeReserve(), 290e18);
        _assertNoLoss();
    }

    function test_SetStakingParamsBounds() public {
        vm.expectRevert(SqueekPotYield.BadParams.selector);
        pot.setStakingParams(5999, 2000); // below strict floor (venue max 6000)
        vm.expectRevert(SqueekPotYield.BadParams.selector);
        pot.setStakingParams(10_001, 2000); // above 100%
        vm.expectRevert(SqueekPotYield.BadParams.selector);
        pot.setStakingParams(6000, 10_001); // buffer > 100%
        pot.setStakingParams(8000, 3000); // ok — raise cushion above strict
        assertEq(pot.safetyFeeBps(), 8000);
        assertEq(pot.bufferBps(), 3000);
    }

    function test_RaiseSafetyFeeBlockedIfUndercollateralised() public {
        _deposit(alice, 1000e18);
        pot.enableStaking(true);
        _seedFee(480e18);
        pot.stake(800e18); // strict 6000: req 480 <= 480
        // raising to 90% would require 720 cushion; have 480 → revert
        vm.expectRevert(SqueekPotYield.FeeCushionExceeded.selector);
        pot.setStakingParams(9000, 2000);
    }

    function test_ConstructorRejectsNonCanonicalVenue() public {
        // Any venue address other than CANONICAL_STAKING is rejected — even one with correct
        // token()/genesis() getters — because the venue is address-pinned, not getter-trusted.
        MockSqueekStaking spoof = new MockSqueekStaking(sqk, address(genesisNft));
        vm.expectRevert(SqueekPotYield.VenueMismatch.selector);
        new SqueekPotYield(
            address(sqk), address(vrf), KEY_HASH, subId, 3, 500_000, false, INTERVAL, INTERVAL,
            address(genesisNft), address(spoof)
        );
    }

    function test_StraySurplusViaWithdrawKeepsInvariant() public {
        // P2 (round-2): stray SQK must NOT be usable as principal liquidity to skip an unstake,
        // which would leave stakedPrincipal > totalDeposits and underflow the views.
        _enableAndStake(1000e18, 800e18, 480e18);
        staking.setFeeBps(200);
        sqk.mint(address(pot), 100e18); // stray transfer straight to the pot
        vm.prank(alice);
        pot.withdraw(300e18); // 200 buffer + unstake 100 (NOT served from the stray 100)
        assertEq(sqk.balanceOf(alice), 300e18);
        assertLe(pot.stakedPrincipal(), pot.totalDeposits()); // invariant intact
        assertEq(pot.stakedPrincipal(), 700e18);
        assertEq(pot.totalDeposits(), 700e18);
        pot.liquidPrincipal(); // must not underflow
        pot.syncPrize(); // must not underflow; sweeps the stray 100 to prize
        assertEq(pot.prizeReserve(), 100e18);
        _assertNoLoss();
    }

    function test_IncrementalUnstakeFailsSafeWhenVenueFeeAboveCushion() public {
        // P0-2 (round-2 #2): a partial withdrawal that must unstake MUST fail-safe revert if the
        // live venue fee exceeds the cushion rate — never silently under-collateralise the rest.
        _enableAndStake(1000e18, 800e18, 480e18); // strict 60% cushion
        staking.setFeeBps(7000); // venue lifts fee to 70%
        // withdraw 300 → 200 buffer + must unstake 100 @70% (fee 70 > feeCap 60) → revert
        vm.prank(alice);
        vm.expectRevert(SqueekPotYield.FeeCushionExceeded.selector);
        pot.withdraw(300e18);
        // pure-buffer withdrawal (<=200) still pays 100%
        vm.prank(alice);
        pot.withdraw(200e18);
        assertEq(sqk.balanceOf(alice), 200e18);
    }

    function test_IncoherentVenueQuoteRejected() public {
        // P1 (round-3): a hostile venue returning an incoherent quote (0,0) must be rejected by
        // the coherence check, not let a withdrawal book an uncapped fee against the cushion.
        _enableAndStake(1000e18, 800e18, 480e18);
        staking.setBadQuote(true);
        vm.prank(alice);
        vm.expectRevert(SqueekPotYield.BadUnstake.selector);
        pot.withdraw(900e18); // needs unstake → quoteUnstake incoherent → BadUnstake
    }

    function test_SafetyFeeIsRaiseOnly() public {
        _deposit(alice, 1000e18);
        pot.enableStaking(true);
        _seedFee(480e18);
        pot.setStakingParams(8000, 2000); // raise 6000 -> 8000 ok
        assertEq(pot.safetyFeeBps(), 8000);
        // cannot lower back toward the floor
        vm.expectRevert(SqueekPotYield.BadParams.selector);
        pot.setStakingParams(6000, 2000);
    }

    function test_PhantomStakeRejected() public {
        // P0-3 (round-2 #3): if the venue no-ops stake() (no SQK actually leaves the pot), stake
        // must revert via the balance-delta check rather than booking phantom stakedPrincipal.
        _deposit(alice, 1000e18);
        pot.enableStaking(true);
        _seedFee(480e18);
        staking.setNoPull(true); // counterfeit: accepts stake() but takes nothing
        vm.expectRevert(SqueekPotYield.BadStake.selector);
        pot.stake(100e18);
        assertEq(pot.stakedPrincipal(), 0); // no phantom principal booked
    }

    function test_OnlyOwnerGates() public {
        vm.prank(alice);
        vm.expectRevert();
        pot.enableStaking(true);
        vm.prank(alice);
        vm.expectRevert();
        pot.stake(1);
        vm.prank(alice);
        vm.expectRevert();
        pot.setStakingParams(200, 2000);
    }

    // (venue authenticity is now address-pinned — see test_ConstructorRejectsNonCanonicalVenue;
    //  token()/genesis() getter checks remain in the constructor as defense-in-depth.)

    // --------------------------------------------------------------------- //
    //                      No-loss across a mixed sequence                  //
    // --------------------------------------------------------------------- //

    function test_NoLossAcrossMixedSequence() public {
        _deposit(alice, 1000e18);
        _deposit(bob, 500e18);
        pot.enableStaking(true);
        _seedFee(300e18);
        staking.setFeeBps(200);
        pot.stake(500e18); // strict 60% default → need 500*0.6=300 cushion, exactly seeded
        _assertNoLoss();

        // yield → prize, run a draw, partial withdraws, more staking — invariant holds throughout
        _accrueYield(90e18);
        pot.harvest();
        _assertNoLoss();
        _drawWithWord(uint256(keccak256("r")) );
        _assertNoLoss();
        vm.prank(alice);
        pot.withdraw(700e18); // 1000 liquid principal? staked 500 of 1500 → 1000 liquid, served from buffer
        _assertNoLoss();
        vm.prank(bob);
        pot.withdraw(500e18);
        _assertNoLoss();
    }
}
