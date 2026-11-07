// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @notice Minimal interface to the Squeekchain staged-launch-1 SQK Staking contract
///         (`0x50fd1780…`, impl v3). Only the SQK-token-staking surface is used — never
///         the NFT `deposit`/`withdraw` path. Verified on-chain + Blockscout.
interface ISqueekStaking {
    /// @notice Stake `amount` SQK (pulled via transferFrom; caller must approve first).
    function stake(uint256 amount) external;
    /// @notice Unstake `amount` nominal staked SQK. Returns the NET received after the
    ///         pressure-based exit fee. `maxFee` caps the fee (reverts `FeeLimitExceeded`
    ///         if the live fee exceeds it); `deadline` is a timestamp guard.
    function unstake(uint256 amount, uint256 maxFee, uint64 deadline) external returns (uint256 netOut);
    /// @notice Claim accrued SQK stream rewards to `to`. Returns the amount sent.
    function claim(address to) external returns (uint256 amount);
    /// @notice Pending claimable SQK rewards for `who`.
    function claimable(address who) external view returns (uint256);
    /// @notice (fee, netOut) for unstaking `amount` from `who` at current pressure.
    function quoteUnstake(address who, uint256 amount) external view returns (uint256 fee, uint256 netOut);
    /// @notice The staked SQK token (must equal this pot's `sqk`).
    function token() external view returns (address);
    /// @notice The Genesis NFT collection this venue is bound to (used to authenticate the venue).
    function genesis() external view returns (address);
    /// @notice The mining/emission engine this venue is bound to (non-zero on the real graph).
    function mining() external view returns (address);
}

/// @title SqueekPotYield — a TRUE no-loss SQK lottery (yield-funded prize) on Squeekchain
/// @author built for the Squeekchain Genesis Buildooooor track
/// @notice Deposit SQK, keep it (always 100% withdrawable), and your deposit size is your
///         odds of winning. The prize is funded by STAKING YIELD on the pooled SQK, not by
///         spending anyone's principal — the actual no-loss model (deposits earn, the yield
///         is the prize, principal is never at risk).
///
/// @dev  ─────────────────────────────────────────────────────────────────────────────────
///       THE NO-LOSS INVARIANT (what an auditor should check FIRST)
///       ─────────────────────────────────────────────────────────────────────────────────
///       Principal (`totalDeposits`) is held in two places: liquid SQK in this contract and
///       SQK staked in the venue (`stakedPrincipal`). The staking venue charges a DYNAMIC
///       exit fee (2%→60%, pressure-based). To keep every depositor whole despite that fee,
///       the contract maintains, at all times:
///
///             feeReserve  >=  stakedPrincipal * safetyFeeBps / 1e4
///
///       `feeReserve` is SQK set aside FROM YIELD (or sponsor seed) solely to absorb exit
///       fees — it is never paid as a prize and never leaves to the owner. When a withdrawal
///       must unstake, the fee is debited from `feeReserve`, so the depositor still receives
///       100% and no OTHER depositor's principal is touched. `safetyFeeBps` is FLOORED at the
///       venue's max (6000 = 60%) and the owner may only RAISE it — so the cushion is always
///       sized for at least the venue's worst-case fee: STRICT always-no-loss that the owner
///       cannot weaken. Accounting uses MEASURED SQK balance deltas around every venue call
///       (claim/unstake), never the venue's returned numbers, so a misbehaving venue cannot
///       book phantom reserves. Residual: if Squeekchain governance ever lifts the venue max
///       ABOVE the current cushion, an unstake-requiring withdrawal fail-safe REVERTS (never
///       short-pays); the owner then raises `safetyFeeBps` and/or `recoverStake`s to de-risk,
///       and liquid-buffer withdrawals are unaffected throughout.
///
///       Three accumulators, never commingled: `totalDeposits` (principal, owed back 1:1),
///       `prizeReserve` (yield earmarked as prize, paid only to winners), `feeReserve` (yield
///       earmarked to absorb exit fees, swept to prize when in excess). A draw only ever pays
///       `prizeReserve`. `withdraw` is NOT pausable.
///
///       SWITCH-ON-LATER: staking is DISABLED at deploy (`stakingEnabled=false`). Until the
///       owner enables it, every deposit stays fully liquid — behaviourally identical to the
///       seeded v1 pot, trivially no-loss. The Squeekchain staking reward stream is currently
///       dry (rate 0); flip `enableStaking(true)` once it is re-funded and the pot begins
///       earning the prize from pooled-SQK yield.
///
///       Randomness / NFT boost / token precondition: identical to v1 SqueekPot — VRF 2.5
///       with a pinned immutable coordinator, tiny fulfill + permissionless O(n) settle,
///       immutable +20% Genesis-NFT boost via a gas/returndata-bounded staticcall, standard
///       non-fee-on-transfer SQK assumed.
contract SqueekPotYield is VRFConsumerBaseV2Plus, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // --------------------------------------------------------------------- //
    //                              Immutables                               //
    // --------------------------------------------------------------------- //

    IERC20 public immutable sqk;
    uint256 public immutable drawInterval;
    address public immutable i_coordinator;
    IERC721 public immutable boostNft;
    /// @notice Squeekchain SQK staking venue (SQK-token staking surface).
    ISqueekStaking public immutable staking;

    /// @notice The canonical Squeekchain staged-launch-1 SQK staking venue on Sepolia. The
    ///         constructor REQUIRES `_staking` to equal this — self-reported getters alone are
    ///         not venue authentication (a counterfeit can mimic them and then keep staked SQK),
    ///         so the venue is pinned to a known address. A mainnet deployment ships a new build
    ///         with the mainnet venue address here.
    address public constant CANONICAL_STAKING = 0x50fd1780526C3186A0c037c7622203bC4fb611ca;

    uint256 public constant MIN_DEPOSIT = 1e18;
    uint256 public constant MAX_PARTICIPANTS = 500;
    uint256 public constant DRAW_TIMEOUT = 1 days;
    uint256 public constant STUCK_FALLBACK_TIMEOUT = 7 days;
    uint256 public constant MAX_TOTAL = type(uint96).max / 2;
    uint256 public constant MAX_BOOST_BPS = 10_000;
    /// @notice The venue's exit-fee ceiling (exitPolicy.maxBps = 6000 = 60%). This is the FLOOR
    ///         for `safetyFeeBps`: the cushion is always sized for AT LEAST the venue's worst-case
    ///         fee, so strict no-loss cannot be weakened below it. The owner may only RAISE the
    ///         cushion (up to MAX_SAFETY_BPS), e.g. if Squeekchain governance ever lifts the
    ///         venue max above 60%.
    uint16 public constant VENUE_MAX_FEE_BPS = 6000;
    /// @notice Absolute cap on the cushion rate (100%).
    uint16 public constant MAX_SAFETY_BPS = 10_000;

    uint256 public immutable boostBps;

    // --------------------------------------------------------------------- //
    //                        VRF config (owner-tunable)                     //
    // --------------------------------------------------------------------- //

    bytes32 public keyHash;
    uint256 public subscriptionId;
    uint16 public requestConfirmations;
    uint32 public callbackGasLimit;
    bool public payInNative;

    // --------------------------------------------------------------------- //
    //                       Staking config (owner-tunable)                  //
    // --------------------------------------------------------------------- //

    /// @notice Master switch. False at deploy → deposits stay fully liquid (v1 behaviour).
    bool public stakingEnabled;
    /// @notice Exit-fee rate the cushion is sized for. Floored at 6000 (venue max) = strict
    ///         always-no-loss; owner may only RAISE it (never weaken below strict).
    uint16 public safetyFeeBps;
    /// @notice Fraction of `totalDeposits` kept liquid as a withdrawal buffer, in bps.
    uint16 public bufferBps;

    // --------------------------------------------------------------------- //
    //                           Deposit accounting                          //
    // --------------------------------------------------------------------- //

    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;
    address[] public participants;
    mapping(address => uint256) private _idxPlus1;

    // --------------------------------------------------------------------- //
    //                       Prize / yield / staking state                   //
    // --------------------------------------------------------------------- //

    /// @notice SQK set aside as prize (from yield or seeding). NEVER from deposits.
    uint256 public prizeReserve;
    /// @notice SQK set aside to absorb staking exit fees. NEVER a prize, NEVER to the owner.
    uint256 public feeReserve;
    /// @notice Nominal SQK currently staked in the venue (principal only). <= totalDeposits.
    uint256 public stakedPrincipal;
    /// @notice Lifetime SQK harvested from the staking stream.
    uint256 public totalYieldHarvested;

    // --------------------------------------------------------------------- //
    //                           Round / draw state                         //
    // --------------------------------------------------------------------- //

    enum DrawState {
        Idle,
        Requested,
        Ready
    }

    DrawState public drawState;
    uint256 public nextDrawTime;
    uint256 public roundId;
    uint256 public pendingRequestId;
    uint256 public requestedAt;
    uint256 public pendingRandomWord;
    uint256 public pendingPrize;

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
    event StakingEnabledSet(bool enabled);
    event StakingParamsUpdated(uint16 safetyFeeBps, uint16 bufferBps);
    event Staked(uint256 amount, uint256 stakedPrincipal);
    event Unstaked(uint256 nominal, uint256 netReceived, uint256 feePaid, uint256 stakedPrincipal);
    event Harvested(uint256 claimed, uint256 toFeeReserve, uint256 toPrize);
    event FeeReserveSeeded(address indexed funder, uint256 amount, uint256 newReserve);
    event FeeReserveSweptToPrize(uint256 amount, uint256 newPrize);

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
    error CoordinatorChanged();
    error TotalCapExceeded();
    error StakingDisabled();
    error BufferBreach();
    error FeeCushionExceeded();
    error BadParams();
    error TokenMismatch();
    error VenueMismatch();
    error Overstake();
    error BadUnstake();
    error BadStake();

    // --------------------------------------------------------------------- //
    //                              Constructor                              //
    // --------------------------------------------------------------------- //

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
        address _boostNft,
        address _staking
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        require(_sqk != address(0), "sqk=0");
        require(_drawInterval > 0, "interval=0");
        require(_boostNft != address(0), "boostNft=0");
        require(_staking != address(0), "staking=0");
        // PRIMARY authentication: the venue is pinned to the canonical Squeekchain staking
        // address. Self-reported getters are not authentication (a counterfeit can mimic them),
        // so address identity is the real binding.
        if (_staking != CANONICAL_STAKING) revert VenueMismatch();
        // Secondary deploy-time sanity (belt-and-suspenders on the pinned venue's wiring): it must
        // stake the SAME SQK we pool and be bound to the SAME Genesis NFT + a non-zero mining.
        if (ISqueekStaking(_staking).token() != _sqk) revert TokenMismatch();
        if (ISqueekStaking(_staking).genesis() != _boostNft) revert VenueMismatch();
        if (ISqueekStaking(_staking).mining() == address(0)) revert VenueMismatch();

        sqk = IERC20(_sqk);
        boostNft = IERC721(_boostNft);
        staking = ISqueekStaking(_staking);
        boostBps = 2000;
        i_coordinator = _vrfCoordinator;
        drawInterval = _drawInterval;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        requestConfirmations = _requestConfirmations;
        callbackGasLimit = _callbackGasLimit;
        payInNative = _payInNative;
        nextDrawTime = block.timestamp + _firstDrawDelay;
        drawState = DrawState.Idle;

        // Safe defaults: staking OFF, cushion sized for the venue's WORST case (strict no-loss),
        // 20% liquid buffer. Owner tunes once the reward stream is live.
        stakingEnabled = false;
        safetyFeeBps = VENUE_MAX_FEE_BPS; // 6000 = strict
        bufferBps = 2000; // 20%
    }

    // --------------------------------------------------------------------- //
    //                           Deposit / Withdraw                          //
    // --------------------------------------------------------------------- //

    /// @notice Deposit SQK into the pot. Increases your odds; never at risk. The SQK stays
    ///         liquid here; a separate owner `stake()` call later puts the excess to work.
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

    /// @notice Withdraw your SQK. Always available in full. Served from the liquid buffer;
    ///         if the buffer is short, the pot unstakes exactly enough and covers the exit
    ///         fee from `feeReserve`, so you still receive 100%.
    function withdraw(uint256 amount) external nonReentrant {
        uint256 bal = deposits[msg.sender];
        if (amount == 0) revert ZeroAmount();
        if (amount > bal) revert InsufficientBalance();

        uint256 remaining = bal - amount;
        if (remaining != 0 && remaining < MIN_DEPOSIT) revert BelowMinimum();

        // Free `amount` of liquid principal FIRST (unstaking the shortfall if the buffer can't
        // cover it), using the CURRENT (pre-decrement) accounting so the accounted-liquid cap in
        // _availableForPrincipal is correct. Guarded by nonReentrant, so the venue call here
        // cannot re-enter. This keeps stakedPrincipal <= totalDeposits after the decrement.
        _ensureLiquid(amount);

        deposits[msg.sender] = remaining;
        totalDeposits -= amount;
        if (remaining == 0) _removeParticipant(msg.sender);

        sqk.safeTransfer(msg.sender, amount);
        emit Withdrew(msg.sender, amount, remaining);
    }

    // --------------------------------------------------------------------- //
    //                       Prize / fee-reserve funding                     //
    // --------------------------------------------------------------------- //

    /// @notice Seed the prize pot with SQK. Permissionless — anyone may sponsor.
    function fundPrize(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 received = _pull(msg.sender, amount);
        prizeReserve += received;
        emit PrizeFunded(msg.sender, received, prizeReserve);
    }

    /// @notice Seed the fee-reserve cushion directly (e.g. to bootstrap staking before yield
    ///         has accrued). Permissionless donation — this SQK can only ever cover exit fees
    ///         or be swept to the prize; it never returns to the funder or the owner.
    function seedFeeReserve(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 received = _pull(msg.sender, amount);
        feeReserve += received;
        emit FeeReserveSeeded(msg.sender, received, feeReserve);
    }

    /// @notice Move any fee-reserve ABOVE the required cushion into the prize. Permissionless;
    ///         benefits players, can never reduce the cushion below its requirement.
    function sweepFeeReserveExcess() external nonReentrant {
        uint256 req = requiredFeeReserve();
        if (feeReserve > req) {
            uint256 extra = feeReserve - req;
            feeReserve = req;
            prizeReserve += extra;
            emit FeeReserveSweptToPrize(extra, prizeReserve);
        }
    }

    /// @notice Sweep stray SQK (sent directly, not via deposit/fund/seed/harvest) into the
    ///         prize. Can only INCREASE the prize; harmless.
    function syncPrize() external nonReentrant {
        uint256 bal = sqk.balanceOf(address(this));
        uint256 liquidPrin = totalDeposits - stakedPrincipal;
        uint256 accounted = liquidPrin + prizeReserve + feeReserve;
        if (bal > accounted) {
            uint256 extra = bal - accounted;
            prizeReserve += extra;
            emit PrizeFunded(address(0), extra, prizeReserve);
        }
    }

    // --------------------------------------------------------------------- //
    //                         Staking (owner / keeper)                      //
    // --------------------------------------------------------------------- //

    /// @notice Stake `amount` of the liquid principal into the venue. Owner-gated. Keeps the
    ///         withdrawal buffer intact AND keeps the fee cushion sized for the new stake, so
    ///         principal is never put at risk by the venue's exit fee.
    function stake(uint256 amount) external onlyOwner nonReentrant {
        if (!stakingEnabled) revert StakingDisabled();
        if (amount == 0) revert ZeroAmount();

        // Only ever stake accounted PRINCIPAL — never stray surplus (which would push
        // stakedPrincipal above totalDeposits and underflow the liquidPrincipal views).
        if (stakedPrincipal + amount > totalDeposits) revert Overstake();

        uint256 avail = _availableForPrincipal();
        uint256 bufferMin = (totalDeposits * bufferBps) / 10_000;
        // Must leave at least the buffer liquid after staking.
        if (avail < amount + bufferMin) revert BufferBreach();
        // Fee cushion must cover the worst-case unwind of the NEW staked total.
        if (feeReserve < ((stakedPrincipal + amount) * safetyFeeBps) / 10_000) revert FeeCushionExceeded();

        // Verify the SQK ACTUALLY left the pot into the venue before crediting stakedPrincipal —
        // a no-op/counterfeit venue cannot create phantom staked principal.
        uint256 beforeBal = sqk.balanceOf(address(this));
        sqk.forceApprove(address(staking), amount);
        staking.stake(amount);
        uint256 sent = beforeBal - sqk.balanceOf(address(this));
        if (sent != amount) revert BadStake();
        sqk.forceApprove(address(staking), 0); // leave no dangling allowance

        stakedPrincipal += amount;
        emit Staked(amount, stakedPrincipal);
    }

    /// @notice Unstake `nominal` SQK back to the liquid buffer (reduce staking exposure).
    ///         Owner-gated. The exit fee is paid from `feeReserve`; principal stays whole.
    function recoverStake(uint256 nominal) external onlyOwner nonReentrant {
        if (nominal == 0) revert ZeroAmount();
        if (nominal > stakedPrincipal) revert Overstake();
        _unstake(nominal);
    }

    /// @notice Harvest accrued staking yield. Permissionless. Tops the fee cushion to its
    ///         requirement first, then routes the remainder into the prize.
    function harvest() external nonReentrant {
        // Measure the ACTUAL SQK received — never trust the venue's returned number.
        uint256 beforeBal = sqk.balanceOf(address(this));
        staking.claim(address(this));
        uint256 got = sqk.balanceOf(address(this)) - beforeBal;
        if (got == 0) return;
        totalYieldHarvested += got;

        uint256 req = requiredFeeReserve();
        uint256 toFee;
        if (feeReserve < req) {
            uint256 gap = req - feeReserve;
            toFee = got < gap ? got : gap;
            feeReserve += toFee;
        }
        uint256 toPrize = got - toFee;
        prizeReserve += toPrize;
        emit Harvested(got, toFee, toPrize);
    }

    // --------------------------------------------------------------------- //
    //                                 Draw                                  //
    // --------------------------------------------------------------------- //

    function requestDraw() external nonReentrant whenNotPaused returns (uint256 requestId) {
        if (drawState != DrawState.Idle) revert DrawBusy();
        if (address(s_vrfCoordinator) != i_coordinator) revert CoordinatorChanged();
        if (block.timestamp < nextDrawTime) revert TooEarly();
        if (totalDeposits == 0) revert NoPlayers();
        if (prizeReserve == 0) revert NoPrize();

        pendingPrize = prizeReserve;
        _freezeEligibility();
        drawState = DrawState.Requested;
        requestedAt = block.timestamp;
        pendingRequestId = type(uint256).max;

        requestId = s_vrfCoordinator.requestRandomWords(
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

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        if (address(s_vrfCoordinator) != i_coordinator) revert CoordinatorChanged();
        if (drawState != DrawState.Requested || requestId != pendingRequestId) return;
        pendingRandomWord = randomWords[0];
        drawState = DrawState.Ready;
        emit DrawReady(roundId, requestId);
    }

    /// @notice Settle a ready draw: pick the weighted winner and pay the prize from
    ///         `prizeReserve` (yield), which is always liquid in this contract.
    function settleDraw() external nonReentrant {
        if (drawState != DrawState.Ready) revert NotReady();

        uint256 rid = roundId;
        uint256 prize = pendingPrize;
        uint256 total = _snapTotal;
        uint256 rand = pendingRandomWord;

        drawState = DrawState.Idle;
        nextDrawTime = block.timestamp + drawInterval;
        roundId = rid + 1;
        pendingRequestId = 0;
        pendingRandomWord = 0;
        pendingPrize = 0;
        requestedAt = 0;

        if (total == 0) {
            _clearSnapshot();
            emit DrawCancelled(rid, "empty snapshot");
            return;
        }

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
        require(winner != address(0), "no winner");

        _clearSnapshot();
        prizeReserve -= prize; // prizeReserve >= prize (snapshot at request; only grows since)
        lastWinner = winner;
        lastPrize = prize;
        totalPaidOut += prize;

        // prizeReserve is never staked, so it is always physically present to pay.
        sqk.safeTransfer(winner, prize);
        emit DrawSettled(rid, winner, prize);
    }

    // --------------------------------------------------------------------- //
    //                          Owner (config only)                          //
    // --------------------------------------------------------------------- //

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

    /// @notice Turn staking on/off. Disabling does not force an unwind (use `recoverStake`);
    ///         it only stops new `stake()` calls.
    function enableStaking(bool enabled) external onlyOwner {
        stakingEnabled = enabled;
        emit StakingEnabledSet(enabled);
    }

    /// @notice Tune the fee cushion and buffer. `_safetyFeeBps` is RAISE-ONLY within
    ///         [VENUE_MAX_FEE_BPS (6000), MAX_SAFETY_BPS (10000)] — it can never go below the
    ///         strict floor nor below its current value — and a raise is allowed only if the
    ///         current `feeReserve` still covers the new requirement (never under-collateralise).
    function setStakingParams(uint16 _safetyFeeBps, uint16 _bufferBps) external onlyOwner {
        // Cushion can never be weakened below strict (the venue max), and is strictly RAISE-ONLY
        // (never reducible, even back toward the floor) — so a cushion grown to match a risen
        // venue max cannot later be lowered and then swept out from under staked principal.
        if (_safetyFeeBps < VENUE_MAX_FEE_BPS || _safetyFeeBps > MAX_SAFETY_BPS) revert BadParams();
        if (_safetyFeeBps < safetyFeeBps) revert BadParams();
        if (_bufferBps > 10_000) revert BadParams();
        if (feeReserve < (stakedPrincipal * _safetyFeeBps) / 10_000) revert FeeCushionExceeded();
        safetyFeeBps = _safetyFeeBps;
        bufferBps = _bufferBps;
        emit StakingParamsUpdated(_safetyFeeBps, _bufferBps);
    }

    function cancelStuckDraw() external onlyOwner {
        _recoverStuck(DRAW_TIMEOUT);
    }

    function forceRecoverStuckDraw() external {
        _recoverStuck(STUCK_FALLBACK_TIMEOUT);
    }

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

    function oddsOf(address user) external view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (deposits[user] * 1e18) / totalDeposits;
    }

    function timeUntilDraw() external view returns (uint256) {
        if (block.timestamp >= nextDrawTime) return 0;
        return nextDrawTime - block.timestamp;
    }

    function holdsBoostNft(address user) external view returns (bool) {
        return _holdsBoostNft(user);
    }

    function canRequestDraw() external view returns (bool) {
        return drawState == DrawState.Idle && block.timestamp >= nextDrawTime && totalDeposits > 0
            && prizeReserve > 0 && !paused() && address(s_vrfCoordinator) == i_coordinator;
    }

    /// @notice SQK required in `feeReserve` to keep the no-loss invariant for the current stake.
    function requiredFeeReserve() public view returns (uint256) {
        return (stakedPrincipal * safetyFeeBps) / 10_000;
    }

    /// @notice Liquid principal SQK available — the physical balance minus the two yield
    ///         reserves, CAPPED at the accounted liquid principal (`totalDeposits -
    ///         stakedPrincipal`). The cap is load-bearing: it stops stray/unsynced surplus from
    ///         being counted as principal (which could otherwise let a withdrawal skip the
    ///         unstake and leave `stakedPrincipal > totalDeposits`, underflowing the views).
    ///         `withdraw` calls `_ensureLiquid` BEFORE decrementing `totalDeposits`, so the
    ///         invariant `totalDeposits >= stakedPrincipal` holds on every call here; the
    ///         subtraction is still guarded defensively.
    function _availableForPrincipal() private view returns (uint256) {
        uint256 bal = sqk.balanceOf(address(this));
        uint256 reserved = prizeReserve + feeReserve;
        uint256 physical = bal > reserved ? bal - reserved : 0;
        uint256 accounted = totalDeposits > stakedPrincipal ? totalDeposits - stakedPrincipal : 0;
        return physical < accounted ? physical : accounted;
    }

    /// @notice Principal SQK currently sitting liquid (not staked) — accounting view.
    function liquidPrincipal() external view returns (uint256) {
        return totalDeposits - stakedPrincipal;
    }

    /// @notice How much the owner could stake right now without breaching buffer, cushion, or
    ///         the principal cap. A conservative (floor) estimate — `stake()` is the source of
    ///         truth; this never over-reports what `stake()` would accept.
    function stakableNow() external view returns (uint256) {
        if (!stakingEnabled) return 0;
        uint256 avail = _availableForPrincipal();
        uint256 bufferMin = (totalDeposits * bufferBps) / 10_000;
        uint256 byBuffer = avail > bufferMin ? avail - bufferMin : 0;
        // Cushion: need feeReserve >= (stakedPrincipal + x) * safetyFeeBps / 1e4. Since stake()'s
        // check floors the product, the largest SAFE total that always satisfies it is
        // floor(feeReserve / safetyFeeBps) * 1e4 (conservative; never over-reports).
        uint256 maxTotalByCushion = safetyFeeBps == 0 ? type(uint256).max : (feeReserve / safetyFeeBps) * 10_000;
        uint256 byCushion = maxTotalByCushion > stakedPrincipal ? maxTotalByCushion - stakedPrincipal : 0;
        // Principal cap: stakedPrincipal + x <= totalDeposits.
        uint256 byPrincipal = totalDeposits > stakedPrincipal ? totalDeposits - stakedPrincipal : 0;
        uint256 r = byBuffer < byCushion ? byBuffer : byCushion;
        return r < byPrincipal ? r : byPrincipal;
    }

    /// @notice Pending (unharvested) SQK yield in the staking venue.
    function pendingYield() external view returns (uint256) {
        return staking.claimable(address(this));
    }

    // --------------------------------------------------------------------- //
    //                               Internal                                //
    // --------------------------------------------------------------------- //

    function _pull(address from, uint256 amount) private returns (uint256 received) {
        uint256 before = sqk.balanceOf(address(this));
        sqk.safeTransferFrom(from, address(this), amount);
        received = sqk.balanceOf(address(this)) - before;
        if (received == 0) revert NothingReceived();
    }

    /// @dev Ensure at least `need` liquid principal SQK is available, unstaking if required.
    ///      The exit fee is debited from `feeReserve`, so `need` SQK of principal becomes
    ///      available without impairing any other depositor. Reverts `FeeCushionExceeded` only
    ///      if the live fee exceeds what the cushion can absorb (impossible in strict mode).
    function _ensureLiquid(uint256 need) private {
        uint256 avail = _availableForPrincipal();
        if (avail >= need) return;
        uint256 shortfall = need - avail;
        if (shortfall > stakedPrincipal) revert InsufficientBalance(); // unreachable if invariant holds
        _unstake(shortfall);
    }

    /// @dev Unstake `nominal` staked SQK; pay the fee from `feeReserve`. Accounting uses the
    ///      MEASURED SQK balance delta (never the venue's returned number): a misbehaving venue
    ///      that under-delivers vs its own quote fail-safe reverts rather than letting a
    ///      withdrawal consume cushion/other-principal. After this, `_availableForPrincipal()`
    ///      rises by exactly `nominal` (actual net received + actual fee reclassified out of the
    ///      cushion) and `stakedPrincipal` falls by `nominal`.
    function _unstake(uint256 nominal) private {
        (uint256 feeQuote, uint256 netQuote) = staking.quoteUnstake(address(this), nominal);
        // The fee must fit within our cushion RATE for exactly this nominal. This is the key
        // guard: it keeps the invariant feeReserve >= stakedPrincipal*safetyFeeBps/1e4 true AFTER
        // the partial unwind (feeReserve-feeActual >= (stakedPrincipal-nominal)*rate), and it
        // fail-safe REVERTS if the venue's live fee ever exceeds safetyFeeBps (e.g. governance
        // lifts the venue max above our cushion) — never silently under-collateralising the rest.
        // Reject an INCOHERENT quote — a hostile/upgraded venue could otherwise return
        // (feeQuote=0, netQuote=0) and then deliver ~nothing, booking a huge feeActual past the
        // cap. A coherent quote means netQuote == nominal - feeQuote and feeQuote <= nominal.
        if (feeQuote > nominal || netQuote != nominal - feeQuote) revert BadUnstake();
        uint256 feeCap = (nominal * safetyFeeBps) / 10_000;
        if (feeQuote > feeCap) revert FeeCushionExceeded();
        if (feeReserve < feeQuote) revert FeeCushionExceeded();

        uint256 beforeBal = sqk.balanceOf(address(this));
        staking.unstake(nominal, feeQuote, type(uint64).max); // return value deliberately ignored
        uint256 got = sqk.balanceOf(address(this)) - beforeBal; // ACTUAL received

        // The venue must deliver at least its quoted net and never more than the nominal, AND the
        // realised fee must not exceed what was quoted (and thus capped and reserved). Enforced
        // explicitly — not merely implied — so a venue that under-delivers vs its own quote
        // fail-safe reverts instead of silently under-collateralising the remaining stake.
        if (got < netQuote || got > nominal) revert BadUnstake();
        uint256 feeActual = nominal - got;
        if (feeActual > feeQuote) revert BadUnstake(); // feeActual <= feeQuote <= feeCap <= feeReserve

        stakedPrincipal -= nominal;
        feeReserve -= feeActual;
        emit Unstaked(nominal, got, feeActual, stakedPrincipal);
    }

    function _freezeEligibility() private {
        _clearSnapshot();
        uint256 cum;
        uint256 bps = boostBps;
        uint256 n = participants.length;
        for (uint256 i = 0; i < n; ++i) {
            address p = participants[i];
            uint256 w = deposits[p];
            if (bps != 0 && _holdsBoostNft(p)) {
                w += w * bps / 10_000;
            }
            cum += w;
            _snap.push((uint256(uint160(p)) << 96) | uint96(cum));
        }
        _snapTotal = cum;
    }

    function _holdsBoostNft(address who) private view returns (bool held) {
        address nft = address(boostNft);
        bytes memory cd = abi.encodeWithSelector(IERC721.balanceOf.selector, who);
        assembly {
            let ok := staticcall(30000, nft, add(cd, 0x20), mload(cd), 0x00, 0x00)
            if and(ok, eq(returndatasize(), 32)) {
                returndatacopy(0x00, 0x00, 0x20)
                held := gt(mload(0x00), 0)
            }
        }
    }

    function _clearSnapshot() private {
        delete _snap;
        _snapTotal = 0;
    }

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
