// SPDX-License-Identifier: MIT
pragma solidity =0.8.26 ^0.8.0 ^0.8.20 ^0.8.4;

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/utils/Errors.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/IOwnable.sol

interface IOwnable {
  function owner() external returns (address);

  function transferOwnership(address recipient) external;

  function acceptOwnership() external;
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol

/// @notice The IVRFSubscriptionV2Plus interface defines the subscription
/// @notice related methods implemented by the V2Plus coordinator.
interface IVRFSubscriptionV2Plus {
  /**
   * @notice Add a consumer to a VRF subscription.
   * @param subId - ID of the subscription
   * @param consumer - New consumer which can use the subscription
   */
  function addConsumer(uint256 subId, address consumer) external;

  /**
   * @notice Remove a consumer from a VRF subscription.
   * @param subId - ID of the subscription
   * @param consumer - Consumer to remove from the subscription
   */
  function removeConsumer(uint256 subId, address consumer) external;

  /**
   * @notice Cancel a subscription
   * @param subId - ID of the subscription
   * @param to - Where to send the remaining LINK to
   */
  function cancelSubscription(uint256 subId, address to) external;

  /**
   * @notice Accept subscription owner transfer.
   * @param subId - ID of the subscription
   * @dev will revert if original owner of subId has
   * not requested that msg.sender become the new owner.
   */
  function acceptSubscriptionOwnerTransfer(uint256 subId) external;

  /**
   * @notice Request subscription owner transfer.
   * @param subId - ID of the subscription
   * @param newOwner - proposed new owner of the subscription
   */
  function requestSubscriptionOwnerTransfer(uint256 subId, address newOwner) external;

  /**
   * @notice Create a VRF subscription.
   * @return subId - A unique subscription id.
   * @dev You can manage the consumer set dynamically with addConsumer/removeConsumer.
   * @dev Note to fund the subscription with LINK, use transferAndCall. For example
   * @dev  LINKTOKEN.transferAndCall(
   * @dev    address(COORDINATOR),
   * @dev    amount,
   * @dev    abi.encode(subId));
   * @dev Note to fund the subscription with Native, use fundSubscriptionWithNative. Be sure
   * @dev  to send Native with the call, for example:
   * @dev COORDINATOR.fundSubscriptionWithNative{value: amount}(subId);
   */
  function createSubscription() external returns (uint256 subId);

  /**
   * @notice Get a VRF subscription.
   * @param subId - ID of the subscription
   * @return balance - LINK balance of the subscription in juels.
   * @return nativeBalance - native balance of the subscription in wei.
   * @return reqCount - Requests count of subscription.
   * @return owner - owner of the subscription.
   * @return consumers - list of consumer address which are able to use this subscription.
   */
  function getSubscription(
    uint256 subId
  )
    external
    view
    returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers);

  /*
   * @notice Check to see if there exists a request commitment consumers
   * for all consumers and keyhashes for a given sub.
   * @param subId - ID of the subscription
   * @return true if there exists at least one unfulfilled request for the subscription, false
   * otherwise.
   */
  function pendingRequestExists(uint256 subId) external view returns (bool);

  /**
   * @notice Paginate through all active VRF subscriptions.
   * @param startIndex index of the subscription to start from
   * @param maxCount maximum number of subscriptions to return, 0 to return all
   * @dev the order of IDs in the list is **not guaranteed**, therefore, if making successive calls, one
   * @dev should consider keeping the blockheight constant to ensure a holistic picture of the contract state
   */
  function getActiveSubscriptionIds(uint256 startIndex, uint256 maxCount) external view returns (uint256[] memory);

  /**
   * @notice Fund a subscription with native.
   * @param subId - ID of the subscription
   * @notice This method expects msg.value to be greater than or equal to 0.
   */
  function fundSubscriptionWithNative(uint256 subId) external payable;
}

// lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol

// End consumer library.
library VRFV2PlusClient {
  // extraArgs will evolve to support new features
  bytes4 public constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));
  struct ExtraArgsV1 {
    bool nativePayment;
  }

  struct RandomWordsRequest {
    bytes32 keyHash;
    uint256 subId;
    uint16 requestConfirmations;
    uint32 callbackGasLimit;
    uint32 numWords;
    bytes extraArgs;
  }

  function _argsToBytes(ExtraArgsV1 memory extraArgs) internal pure returns (bytes memory bts) {
    return abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs);
  }
}

// lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert Errors.FailedCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {Errors.FailedCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {Errors.FailedCall}) in case
     * of an unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {Errors.FailedCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {Errors.FailedCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            assembly ("memory-safe") {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert Errors.FailedCall();
        }
    }
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/access/ConfirmedOwnerWithProposal.sol

/// @title The ConfirmedOwner contract
/// @notice A contract with helpers for basic contract ownership.
contract ConfirmedOwnerWithProposal is IOwnable {
  address private s_owner;
  address private s_pendingOwner;

  event OwnershipTransferRequested(address indexed from, address indexed to);
  event OwnershipTransferred(address indexed from, address indexed to);

  constructor(address newOwner, address pendingOwner) {
    // solhint-disable-next-line gas-custom-errors
    require(newOwner != address(0), "Cannot set owner to zero");

    s_owner = newOwner;
    if (pendingOwner != address(0)) {
      _transferOwnership(pendingOwner);
    }
  }

  /// @notice Allows an owner to begin transferring ownership to a new address.
  function transferOwnership(address to) public override onlyOwner {
    _transferOwnership(to);
  }

  /// @notice Allows an ownership transfer to be completed by the recipient.
  function acceptOwnership() external override {
    // solhint-disable-next-line gas-custom-errors
    require(msg.sender == s_pendingOwner, "Must be proposed owner");

    address oldOwner = s_owner;
    s_owner = msg.sender;
    s_pendingOwner = address(0);

    emit OwnershipTransferred(oldOwner, msg.sender);
  }

  /// @notice Get the current owner
  function owner() public view override returns (address) {
    return s_owner;
  }

  /// @notice validate, transfer ownership, and emit relevant events
  function _transferOwnership(address to) private {
    // solhint-disable-next-line gas-custom-errors
    require(to != msg.sender, "Cannot transfer to self");

    s_pendingOwner = to;

    emit OwnershipTransferRequested(s_owner, to);
  }

  /// @notice validate access
  function _validateOwnership() internal view {
    // solhint-disable-next-line gas-custom-errors
    require(msg.sender == s_owner, "Only callable by owner");
  }

  /// @notice Reverts if called by anyone other than the contract owner.
  modifier onlyOwner() {
    _validateOwnership();
    _;
  }
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol

// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC165.sol)

// lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC20.sol)

// lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/IERC721.sol)

/**
 * @dev Required interface of an ERC-721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC-721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
     *   {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC-721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/utils/Pausable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/access/ConfirmedOwner.sol

/// @title The ConfirmedOwner contract
/// @notice A contract with helpers for basic contract ownership.
contract ConfirmedOwner is ConfirmedOwnerWithProposal {
  constructor(address newOwner) ConfirmedOwnerWithProposal(newOwner, address(0)) {}
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol

// Interface that enables consumers of VRFCoordinatorV2Plus to be future-proof for upgrades
// This interface is supported by subsequent versions of VRFCoordinatorV2Plus
interface IVRFCoordinatorV2Plus is IVRFSubscriptionV2Plus {
  /**
   * @notice Request a set of random words.
   * @param req - a struct containing following fields for randomness request:
   * keyHash - Corresponds to a particular oracle job which uses
   * that key for generating the VRF proof. Different keyHash's have different gas price
   * ceilings, so you can select a specific one to bound your maximum per request cost.
   * subId  - The ID of the VRF subscription. Must be funded
   * with the minimum subscription balance required for the selected keyHash.
   * requestConfirmations - How many blocks you'd like the
   * oracle to wait before responding to the request. See SECURITY CONSIDERATIONS
   * for why you may want to request more. The acceptable range is
   * [minimumRequestBlockConfirmations, 200].
   * callbackGasLimit - How much gas you'd like to receive in your
   * fulfillRandomWords callback. Note that gasleft() inside fulfillRandomWords
   * may be slightly less than this amount because of gas used calling the function
   * (argument decoding etc.), so you may need to request slightly more than you expect
   * to have inside fulfillRandomWords. The acceptable range is
   * [0, maxGasLimit]
   * numWords - The number of uint256 random values you'd like to receive
   * in your fulfillRandomWords callback. Note these numbers are expanded in a
   * secure way by the VRFCoordinator from a single random value supplied by the oracle.
   * extraArgs - abi-encoded extra args
   * @return requestId - A unique identifier of the request. Can be used to match
   * a request to a response in fulfillRandomWords.
   */
  function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req) external returns (uint256 requestId);
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol

// OpenZeppelin Contracts (last updated v5.1.0) (interfaces/IERC1363.sol)

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

// src/PinnedVRFConsumerV2Plus.sol

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

// lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Opposedly, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
    }
}

// src/SqueekPot.sol

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
