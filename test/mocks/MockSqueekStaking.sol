// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Faithful mock of the Squeekchain SQK staking venue for SqueekPotYield tests.
///         Models: stake (pull), unstake with a configurable pressure fee + maxFee guard +
///         deadline, pull-style claim of a settable reward, and quoteUnstake. The fee is
///         retained by the mock (the "venue"), exactly like the real exit tax.
contract MockSqueekStaking {
    using SafeERC20 for IERC20;

    IERC20 public immutable tok;
    address public immutable genesisNft;
    uint256 public feeBps = 200; // default 2% (venue floor)
    bool public noPull; // test toggle: when true, stake() does NOT pull SQK (counterfeit venue)
    bool public badQuote; // test toggle: when true, quoteUnstake returns an incoherent (0,0)
    mapping(address => uint256) public staked;
    mapping(address => uint256) public pending; // claimable rewards per staker

    constructor(IERC20 _t, address _genesis) {
        tok = _t;
        genesisNft = _genesis;
    }

    function token() external view returns (address) {
        return address(tok);
    }

    function genesis() external view returns (address) {
        return genesisNft;
    }

    function mining() external view returns (address) {
        return address(0xBEEF); // non-zero, like the real venue's mining engine
    }

    // ---- test harness knobs ----
    function setFeeBps(uint256 b) external {
        feeBps = b;
    }

    function setNoPull(bool v) external {
        noPull = v;
    }

    function setBadQuote(bool v) external {
        badQuote = v;
    }

    /// @dev Credit `who` with `amt` claimable rewards. The harness must also fund this mock
    ///      with `amt` SQK so claim can pay out (mirrors the venue's funded reward stream).
    function addReward(address who, uint256 amt) external {
        pending[who] += amt;
    }

    // ---- venue surface used by SqueekPotYield ----
    function stake(uint256 amount) external {
        if (noPull) return; // counterfeit venue: accept the call but take nothing
        tok.safeTransferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
    }

    function quoteUnstake(address who, uint256 amount) public view returns (uint256 fee, uint256 netOut) {
        require(amount <= staked[who], "overstake");
        if (badQuote) return (0, 0); // incoherent: netOut != amount - fee
        fee = (amount * feeBps) / 10_000;
        netOut = amount - fee;
    }

    function unstake(uint256 amount, uint256 maxFee, uint64 deadline) external returns (uint256) {
        require(block.timestamp <= deadline, "deadline");
        (uint256 fee, uint256 netOut) = quoteUnstake(msg.sender, amount);
        require(fee <= maxFee, "FeeLimitExceeded");
        staked[msg.sender] -= amount;
        tok.safeTransfer(msg.sender, netOut); // the `fee` stays here (venue keeps it)
        return netOut;
    }

    function claimable(address who) external view returns (uint256) {
        return pending[who];
    }

    function claim(address to) external returns (uint256) {
        uint256 amt = pending[msg.sender];
        pending[msg.sender] = 0;
        if (amt > 0) tok.safeTransfer(to, amt);
        return amt;
    }
}
