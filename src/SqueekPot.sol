// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PinnedVRFConsumerV2Plus} from "./PinnedVRFConsumerV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @title SqueekPot — a no-loss SQK lottery on Squeekchain (Sepolia)
/// @author built for the Squeekchain Genesis Buildooooor track
/// @notice Deposit SQK, keep it (always 100% withdrawable), and your deposit size
///         is your odds of winning the daily prize. Your principal is NEVER at risk.
///
/// @dev  THE NO-LOSS INVARIANT (the single property an auditor should check first):
///       user deposits and the prize pot are tracked in TWO separate accumulators —
///       `totalDeposits` and `prizeReserve`. The contract never pays a prize out of
///       `totalDeposits`; a draw only ever transfers `prizeReserve`. Therefore the
///       token balance held is always >= `totalDeposits`, so every depositor can
///       always withdraw their full balance. `withdraw` is deliberately NOT pausable.
///
///       Prize funding (v1 = "seeded"): anyone calls `fundPrize` to top up the pot.
///       A future v2 ("yield") can stake pooled SQK into Squeek staking and route the
///       yield into `prizeReserve` — deposits stay 100% withdrawable either way. v2 is
///       a separate, separately-audited iteration; this contract is seeded-only.
///
///       Randomness: Chainlink VRF 2.5 (subscription). The VRF callback only STORES
///       the random word (fixed gas); a separate permissionless `settleDraw()` does
///       the O(n) weighted winner pick + payout, so the callback can never run out of
///       gas as the player set grows.
///
///       NFT BOOST: holding ≥1 Squeek Genesis NFT (`boostNft`) multiplies your ticket weight at the
///       draw snapshot by `(1 + boostBps/1e4)` — a fixed, immutable +20% (hard-capped at +100%).
///       Still no-loss (deposits untouched); only the odds weighting changes. The NFT read is a
///       gas- and returndata-bounded, failure-tolerant staticcall, so a misbehaving collection
///       cannot brick a draw.
///
///       TOKEN PRECONDITION: SQK is assumed a standard ERC-20 — fixed-supply,
///       non-rebasing, non-fee-on-transfer, non-blocklisting, and WITHOUT transfer
///       hooks (no ERC-777-style callbacks). staged-launch-1 SQK meets this. A
///       fee-on-transfer token breaks the 100%-back promise on exit; a negative rebase
///       can drop the held balance below totalDeposits. Do not repoint to a
///       non-standard token without re-auditing.
contract SqueekPot is PinnedVRFConsumerV2Plus, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // --------------------------------------------------------------------- //
    //                              Immutables                               //
    // --------------------------------------------------------------------- //

    /// @notice The SQK token used for both deposits and prizes.
    IERC20 public immutable sqk;
    /// @notice Seconds between draws (set to 1 days for the live deployment).
    uint256 public immutable drawInterval;
    /// @notice VRF coordinator is pinned IMMUTABLY as `PinnedVRFConsumerV2Plus.vrfCoordinator`
    ///         and there is deliberately NO `setCoordinator` — the owner cannot swap it to make a
    ///         legitimate callback fail and then re-roll the draw (the censorship vector a stock
    ///         `VRFConsumerBaseV2Plus` would expose). Coordinator migration = redeploy.

    /// @notice Squeek Genesis NFT collection. Holding ≥1 boosts your ticket weight at the draw
    ///         snapshot. Immutable by design — an owner-settable collection would let the owner
    ///         point it at an NFT only they hold and rig their own odds; a collection change is a
    ///         redeploy. The boost SIZE is also fixed at deploy (see `boostBps`) and hard-capped.
    IERC721 public immutable boostNft;

    /// @notice Minimum position size — anti-dust floor so the bounded player list
    ///         cannot be cheaply flooded. Odds-neutral (does not change payouts).
    uint256 public constant MIN_DEPOSIT = 1e18; // 1 SQK (18 decimals)
    /// @notice Hard cap on simultaneous players; bounds `settleDraw` gas.
    uint256 public constant MAX_PARTICIPANTS = 500;
    /// @notice If VRF never fulfills, the owner may unstick a draw after this delay.
    uint256 public constant DRAW_TIMEOUT = 1 days;
    /// @notice After this grace period ANYONE may recover a stuck draw (lost-owner-key safety).
    uint256 public constant STUCK_FALLBACK_TIMEOUT = 7 days;
    /// @notice Deposits are rejected once the pot total would exceed this, so cumulative
    ///         weight always fits the packed uint96 in the snapshot. Half of uint96 so that even a
    ///         fully-boosted cumulative weight (≤ 2× total) still fits (~3.9e10 SQK — beyond any use).
    uint256 public constant MAX_TOTAL = type(uint96).max / 2;
    /// @notice Hard ceiling (100%) on the NFT-holder odds boost. The fixed `boostBps` always
    ///         respects this; the packed-weight bound relies on it (boosted weight ≤ 2× deposit).
    uint256 public constant MAX_BOOST_BPS = 10_000;

    // --------------------------------------------------------------------- //
    //                        VRF config (owner-tunable)                     //
    // --------------------------------------------------------------------- //
    // The owner may tune ONLY VRF plumbing. There is no owner power over funds,
    // deposits, the prize, or anyone's odds.

    bytes32 public keyHash;
    uint256 public subscriptionId;
    uint16 public requestConfirmations;
    uint32 public callbackGasLimit;
    bool public payInNative;

    /// @notice Genesis-NFT-holder odds boost, in basis points (2000 = +20%), applied equally to
    ///         every holder. IMMUTABLE — fixed at deploy, not owner-tunable, so the owner cannot
    ///         crank their own cohort's odds before a draw (closes the owner-self-tilt vector).
    ///         Changing it is a redeploy. Always <= MAX_BOOST_BPS, which the packed-weight bound relies on.
    uint256 public immutable boostBps;

    // --------------------------------------------------------------------- //
    //                           Deposit accounting                          //
    // --------------------------------------------------------------------- //

    mapping(address => uint256) public deposits; // user => SQK deposited (== ticket weight)
    uint256 public totalDeposits; // sum of all deposits (== total tickets)
    address[] public participants; // active depositors
    mapping(address => uint256) private _idxPlus1; // participant index + 1 (0 = not a participant)

    // --------------------------------------------------------------------- //
    //                                 Prize                                 //
    // --------------------------------------------------------------------- //

    /// @notice SQK set aside as prize. NEVER sourced from deposits.
    uint256 public prizeReserve;

    // --------------------------------------------------------------------- //
    //                           Round / draw state                         //
    // --------------------------------------------------------------------- //

    enum DrawState {
        Idle, // no draw in flight; a new one may be requested once nextDrawTime passes
        Requested, // VRF randomness requested, awaiting fulfillment
        Ready // randomness received, awaiting settleDraw()
    }

    DrawState public drawState;
    uint256 public nextDrawTime; // earliest timestamp a draw may be requested
    uint256 public roundId; // increments on every settle/cancel
    uint256 public pendingRequestId;
    uint256 public requestedAt; // timestamp the current request was made
    uint256 public pendingRandomWord;
    uint256 public pendingPrize; // prize snapshot taken at request time

    // Eligibility snapshot FROZEN at requestDraw. The winner is picked from this,
    // not from live state, so deposits/withdrawals after a request only affect the
    // NEXT round and cannot move the winning slot once the random word is public.
    // Packed to halve the per-participant SSTORE cost of the freeze (P1 gas-wedge fix):
    //   each entry = (uint160(participant) << 96) | uint96(cumulativeWeight).
    // cumulativeWeight fits uint96 because `deposit` rejects any total > MAX_TOTAL.
    uint256[] private _snap;
    uint256 private _snapTotal;

    // --------------------------------------------------------------------- //
    //                                 Stats                                 //
    // --------------------------------------------------------------------- //

    address public lastWinner;
    uint256 public lastPrize;
    uint256 public totalPaidOut;

    // --------------------------------------------------------------------- //
    //                                 Events                                //
    // --------------------------------------------------------------------- //

    event Deposited(address indexed user, uint256 amount, uint256 newBalance);
    event Withdrew(address indexed user, uint256 amount, uint256 newBalance);
    event PrizeFunded(address indexed funder, uint256 amount, uint256 newReserve);
    event DrawRequested(uint256 indexed roundId, uint256 requestId, uint256 prize);
    event DrawReady(uint256 indexed roundId, uint256 requestId);
    event DrawSettled(uint256 indexed roundId, address indexed winner, uint256 prize);
    event DrawCancelled(uint256 indexed roundId, string reason);
    event VrfConfigUpdated(bytes32 keyHash, uint256 subscriptionId, uint16 confirmations, uint32 callbackGasLimit, bool payInNative);

    // --------------------------------------------------------------------- //
    //                               Errors                                  //
    // --------------------------------------------------------------------- //

    error ZeroAmount();
    error BelowMinimum();
    error PotFull();
    error InsufficientBalance();
    error DrawBusy();
    error TooEarly();
    error NoPlayers();
    error NoPrize();
    error NotReady();
    error NotStuck();
    error NothingReceived();
    error TotalCapExceeded();

    // --------------------------------------------------------------------- //
    //                              Constructor                              //
    // --------------------------------------------------------------------- //

    /// @param _sqk SQK token address (Squeekchain staged-launch-1 SQK on Sepolia).
    /// @param _vrfCoordinator Chainlink VRF 2.5 coordinator.
    /// @param _keyHash VRF gas-lane key hash.
    /// @param _subscriptionId VRF subscription id (this contract must be a consumer).
    /// @param _requestConfirmations VRF confirmations before fulfillment.
    /// @param _callbackGasLimit gas budget for `rawFulfillRandomWords` (kept small; see dev note).
    /// @param _payInNative true = pay VRF in native ETH, false = pay in LINK.
    /// @param _drawInterval seconds between draws (1 days live).
    /// @param _firstDrawDelay seconds from deploy until the first draw may be requested.
    /// @param _boostNft Squeek Genesis NFT collection; holding ≥1 boosts your draw weight.
    constructor(
        address _sqk,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        bool _payInNative,
        uint256 _drawInterval,
        uint256 _firstDrawDelay,
        address _boostNft
    ) PinnedVRFConsumerV2Plus(_vrfCoordinator) {
        require(_sqk != address(0), "sqk=0");
        require(_drawInterval > 0, "interval=0");
        require(_boostNft != address(0), "boostNft=0");
        sqk = IERC20(_sqk);
        boostNft = IERC721(_boostNft);
        boostBps = 2000; // +20% for Squeek Genesis NFT holders (immutable, hard-capped by MAX_BOOST_BPS)
        drawInterval = _drawInterval;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        requestConfirmations = _requestConfirmations;
        callbackGasLimit = _callbackGasLimit;
        payInNative = _payInNative;
        nextDrawTime = block.timestamp + _firstDrawDelay;
        drawState = DrawState.Idle;
    }

    // --------------------------------------------------------------------- //
    //                           Deposit / Withdraw                          //
    // --------------------------------------------------------------------- //

    /// @notice Deposit SQK into the pot. Increases your odds; never at risk.
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        uint256 received = _pull(msg.sender, amount);
        uint256 newBalance = deposits[msg.sender] + received;
        if (newBalance < MIN_DEPOSIT) revert BelowMinimum();
        if (totalDeposits + received > MAX_TOTAL) revert TotalCapExceeded();

        if (_idxPlus1[msg.sender] == 0) {
            if (participants.length >= MAX_PARTICIPANTS) revert PotFull();
            participants.push(msg.sender);
            _idxPlus1[msg.sender] = participants.length;
        }

        deposits[msg.sender] = newBalance;
        totalDeposits += received;
        emit Deposited(msg.sender, received, newBalance);
    }

    /// @notice Withdraw your SQK. Always available in full, even when paused or
    ///         while a draw is in flight. A partial withdrawal must leave either 0
    ///         or at least MIN_DEPOSIT behind.
    function withdraw(uint256 amount) external nonReentrant {
        uint256 bal = deposits[msg.sender];
        if (amount == 0) revert ZeroAmount();
        if (amount > bal) revert InsufficientBalance();

        uint256 remaining = bal - amount;
        if (remaining != 0 && remaining < MIN_DEPOSIT) revert BelowMinimum();

        deposits[msg.sender] = remaining;
        totalDeposits -= amount;
        if (remaining == 0) _removeParticipant(msg.sender);

        // Always satisfiable: balance held >= totalDeposits (prizeReserve is separate).
        sqk.safeTransfer(msg.sender, amount);
        emit Withdrew(msg.sender, amount, remaining);
    }

    // --------------------------------------------------------------------- //
    //                              Prize funding                            //
    // --------------------------------------------------------------------- //

    /// @notice Seed the prize pot with SQK. Permissionless — anyone may sponsor.
    function fundPrize(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 received = _pull(msg.sender, amount);
        prizeReserve += received;
        emit PrizeFunded(msg.sender, received, prizeReserve);
    }

    /// @notice Sweep any SQK sent directly to the contract (unaccounted surplus)
    ///         into the prize pot. Can only ever INCREASE the prize; harmless.
    function syncPrize() external nonReentrant {
        uint256 bal = sqk.balanceOf(address(this));
        uint256 accounted = totalDeposits + prizeReserve;
        if (bal > accounted) {
            uint256 extra = bal - accounted;
            prizeReserve += extra;
            emit PrizeFunded(address(0), extra, prizeReserve);
        }
    }

    // --------------------------------------------------------------------- //
    //                                 Draw                                  //
    // --------------------------------------------------------------------- //

    /// @notice Request the daily draw. Permissionless once the interval has elapsed.
    function requestDraw() external nonReentrant whenNotPaused returns (uint256 requestId) {
        if (drawState != DrawState.Idle) revert DrawBusy();
        if (block.timestamp < nextDrawTime) revert TooEarly();
        if (totalDeposits == 0) revert NoPlayers();
        if (prizeReserve == 0) revert NoPrize();

        pendingPrize = prizeReserve; // snapshot; later funding rolls to next round
        _freezeEligibility(); // lock player set + weights for this round
        drawState = DrawState.Requested;
        requestedAt = block.timestamp;
        // Awaiting-id sentinel: before the external request, no in-flight id exists, so a
        // re-entrant fulfillRandomWords(0,...) must NOT satisfy `requestId == pendingRequestId`.
        pendingRequestId = type(uint256).max;

        requestId = vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: payInNative}))
            })
        );
        pendingRequestId = requestId;
        emit DrawRequested(roundId, requestId, pendingPrize);
    }

    /// @notice Coordinator-only randomness callback (reached only via rawFulfillRandomWords).
    /// @dev Kept intentionally tiny (fixed gas): just records the word and flips state.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        // Coordinator is immutable (PinnedVRFConsumerV2Plus) and rawFulfillRandomWords already
        // authenticates msg.sender against it, so only the real coordinator can reach here.
        // Ignore anything that isn't the request we're waiting on.
        if (drawState != DrawState.Requested || requestId != pendingRequestId) return;
        pendingRandomWord = randomWords[0];
        drawState = DrawState.Ready;
        emit DrawReady(roundId, requestId);
    }

    /// @notice Settle a ready draw: pick the weighted winner and pay the prize.
    ///         Permissionless. O(n) over players — bounded by MAX_PARTICIPANTS.
    function settleDraw() external nonReentrant {
        if (drawState != DrawState.Ready) revert NotReady();

        uint256 rid = roundId;
        uint256 prize = pendingPrize;
        uint256 total = _snapTotal; // frozen at requestDraw — tamper-proof
        uint256 rand = pendingRandomWord;

        // Effects first (checks-effects-interactions): close out the round.
        drawState = DrawState.Idle;
        nextDrawTime = block.timestamp + drawInterval;
        roundId = rid + 1;
        pendingRequestId = 0;
        pendingRandomWord = 0;
        pendingPrize = 0;
        requestedAt = 0;

        // Empty snapshot (unreachable: request gated totalDeposits > 0). Roll forward.
        if (total == 0) {
            _clearSnapshot();
            emit DrawCancelled(rid, "empty snapshot");
            return;
        }

        // Weighted selection over the FROZEN snapshot: a random point in [0, total)
        // lands in exactly one entry's cumulative range. Immune to any deposit or
        // withdrawal that happened after the request.
        uint256 target = rand % total;
        address winner;
        uint256 n = _snap.length;
        for (uint256 i = 0; i < n; ++i) {
            uint256 packed = _snap[i];
            if (target < uint96(packed)) {
                winner = address(uint160(packed >> 96));
                break;
            }
        }
        require(winner != address(0), "no winner"); // unreachable: target < total

        _clearSnapshot();
        // prizeReserve >= prize always (snapshot at request; only increases since).
        prizeReserve -= prize;
        lastWinner = winner;
        lastPrize = prize;
        totalPaidOut += prize;

        sqk.safeTransfer(winner, prize);
        emit DrawSettled(rid, winner, prize);
    }

    // --------------------------------------------------------------------- //
    //                          Owner (VRF plumbing only)                    //
    // --------------------------------------------------------------------- //

    /// @notice Tune VRF parameters. No effect on funds, odds, or draw timing.
    ///         Only permitted while no draw is in flight.
    function setVrfConfig(
        bytes32 _keyHash,
        uint256 _subscriptionId,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        bool _payInNative
    ) external onlyOwner {
        if (drawState != DrawState.Idle) revert DrawBusy();
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        requestConfirmations = _requestConfirmations;
        callbackGasLimit = _callbackGasLimit;
        payInNative = _payInNative;
        emit VrfConfigUpdated(_keyHash, _subscriptionId, _requestConfirmations, _callbackGasLimit, _payInNative);
    }

    /// @notice Owner recovery from a draw stuck in Requested (VRF never fulfilled) after
    ///         DRAW_TIMEOUT. Does NOT touch funds; the prize rolls into the next round.
    ///         A Ready draw is deliberately NOT recoverable — see `_recoverStuck`.
    function cancelStuckDraw() external onlyOwner {
        _recoverStuck(DRAW_TIMEOUT);
    }

    /// @notice Permissionless fallback: if the owner key is lost, ANYONE may recover a
    ///         draw stuck in Requested after STUCK_FALLBACK_TIMEOUT, so a VRF that never
    ///         fulfils can't freeze draws forever. (Ready draws are never recoverable.)
    function forceRecoverStuckDraw() external {
        _recoverStuck(STUCK_FALLBACK_TIMEOUT);
    }

    /// @dev Return the machine to Idle from a stuck *Requested* draw once `delay` has
    ///      elapsed since the request. Prize untouched (rolls forward); deposits never
    ///      touched. REQUESTED-ONLY by design: a Ready draw has a determined, public
    ///      winner and MUST stay settleable — allowing recovery from Ready would let the
    ///      owner (or the 7-day public path) censor an unfavorable, already-randomized
    ///      outcome, reopening an owner-rig vector. Under the standard-token precondition
    ///      `settleDraw`'s transfer cannot be blocked, so a Ready draw never gets stuck.
    function _recoverStuck(uint256 delay) private {
        if (drawState != DrawState.Requested) revert NotStuck();
        if (block.timestamp < requestedAt + delay) revert NotStuck();
        uint256 rid = roundId;
        drawState = DrawState.Idle;
        nextDrawTime = block.timestamp + drawInterval;
        roundId = rid + 1;
        pendingRequestId = 0;
        pendingRandomWord = 0;
        pendingPrize = 0;
        requestedAt = 0;
        _clearSnapshot();
        emit DrawCancelled(rid, "stuck draw recovered");
    }

    /// @notice Pause deposits and new draw requests. Withdrawals and settlement of an
    ///         in-flight draw remain enabled by design.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // --------------------------------------------------------------------- //
    //                                 Views                                 //
    // --------------------------------------------------------------------- //

    function participantCount() external view returns (uint256) {
        return participants.length;
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
    }

    /// @notice Your current win probability, scaled to 1e18 (1e18 == 100%).
    function oddsOf(address user) external view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (deposits[user] * 1e18) / totalDeposits;
    }

    /// @notice Seconds until the next draw may be requested (0 if already eligible).
    function timeUntilDraw() external view returns (uint256) {
        if (block.timestamp >= nextDrawTime) return 0;
        return nextDrawTime - block.timestamp;
    }

    /// @notice Whether `user` currently holds a boost NFT (so their deposit is weighted up).
    function holdsBoostNft(address user) external view returns (bool) {
        return _holdsBoostNft(user);
    }

    /// @notice Whether `requestDraw` would currently succeed.
    function canRequestDraw() external view returns (bool) {
        return drawState == DrawState.Idle && block.timestamp >= nextDrawTime && totalDeposits > 0
            && prizeReserve > 0 && !paused();
    }

    // --------------------------------------------------------------------- //
    //                               Internal                                //
    // --------------------------------------------------------------------- //

    /// @dev Pulls `amount` of SQK from `from`, returning the ACTUAL amount received
    ///      (robust against fee-on-transfer tokens).
    function _pull(address from, uint256 amount) private returns (uint256 received) {
        uint256 before = sqk.balanceOf(address(this));
        sqk.safeTransferFrom(from, address(this), amount);
        received = sqk.balanceOf(address(this)) - before;
        if (received == 0) revert NothingReceived();
    }

    /// @dev Freeze the current player set + cumulative weights for the live round,
    ///      so settlement is immune to post-randomness deposit/withdraw tampering.
    function _freezeEligibility() private {
        _clearSnapshot();
        uint256 cum;
        uint256 bps = boostBps; // cache; when 0 the per-holder NFT read is skipped entirely
        uint256 n = participants.length;
        for (uint256 i = 0; i < n; ++i) {
            address p = participants[i];
            uint256 w = deposits[p];
            if (bps != 0 && _holdsBoostNft(p)) {
                w += w * bps / 10_000; // boosted weight; <= 2x deposit (bps <= MAX_BOOST_BPS)
            }
            cum += w;
            // cum <= 2 * totalDeposits <= 2 * MAX_TOTAL == uint96.max - 1 < uint96.max, lossless pack.
            _snap.push((uint256(uint160(p)) << 96) | uint96(cum));
        }
        _snapTotal = cum; // boosted total weight for this round
    }

    /// @dev Does `who` hold at least one boost NFT? The read is gas-bounded (30k — ample for a
    ///      standard O(1) balanceOf) and copies AT MOST 32 bytes of return data (zero-length output
    ///      buffer, `returndatasize()==32` gate), so a reverting, gas-burning, or returndata-bombing
    ///      collection yields NO boost instead of bricking a draw — regardless of its code.
    function _holdsBoostNft(address who) private view returns (bool held) {
        address nft = address(boostNft);
        bytes memory cd = abi.encodeWithSelector(IERC721.balanceOf.selector, who);
        assembly {
            // staticcall with a 30k stipend and a ZERO-length output buffer (no auto-copy of returndata).
            let ok := staticcall(30000, nft, add(cd, 0x20), mload(cd), 0x00, 0x00)
            // Accept ONLY a well-formed 32-byte return; copy exactly those 32 bytes, never more.
            if and(ok, eq(returndatasize(), 32)) {
                returndatacopy(0x00, 0x00, 0x20)
                held := gt(mload(0x00), 0)
            }
        }
    }

    /// @dev Release the eligibility snapshot (frees storage between rounds).
    function _clearSnapshot() private {
        delete _snap;
        _snapTotal = 0;
    }

    /// @dev Swap-and-pop removal from the participant list.
    function _removeParticipant(address user) private {
        uint256 idx = _idxPlus1[user] - 1;
        uint256 lastIdx = participants.length - 1;
        if (idx != lastIdx) {
            address moved = participants[lastIdx];
            participants[idx] = moved;
            _idxPlus1[moved] = idx + 1;
        }
        participants.pop();
        _idxPlus1[user] = 0;
    }
}
