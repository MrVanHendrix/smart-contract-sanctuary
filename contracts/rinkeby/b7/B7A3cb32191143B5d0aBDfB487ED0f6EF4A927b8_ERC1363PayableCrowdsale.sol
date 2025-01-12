// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../token/ERC20/utils/SafeERC20.sol";
import "../security/ReentrancyGuard.sol";
import "../payment/ERC1363Payable.sol";


contract ERC1363PayableCrowdsale is ERC1363Payable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // The token being sold
  IERC20 private _token;

  // Address where funds are collected
  address private _wallet;

  // How many token units a buyer gets per ERC1363 token
  uint256 private _rate;

  // Amount of ERC1363 token raised
  uint256 private _tokenRaised;

  /**
   * Event for token purchase logging
   * @param operator who called function
   * @param beneficiary who got the tokens
   * @param value ERC1363 tokens paid for purchase
   * @param amount amount of tokens purchased
   */
  event TokensPurchased(
    address indexed operator,
    address indexed beneficiary,
    uint256 value,
    uint256 amount
  );

  /**
   * @param rate_ Number of token units a buyer gets per ERC1363 token
   * @param wallet_ Address where collected funds will be forwarded to
   * @param token_ Address of the token being sold
   * @param acceptedToken_ Address of the token being accepted
   */
  constructor(
    uint256 rate_,
    address wallet_,
    IERC20 token_,
    IERC1363 acceptedToken_
  ) ERC1363Payable(acceptedToken_) {
    require(rate_ > 0);
    require(wallet_ != address(0));
    require(address(token_) != address(0));

    _rate = rate_;
    _wallet = wallet_;
    _token = token_;
  }

  /**
   * @return the token being sold.
   */
  function token() public view returns (IERC20) {
    return _token;
  }

  /**
   * @return the address where funds are collected.
   */
  function wallet() public view returns (address) {
    return _wallet;
  }

  /**
   * @return the number of token units a buyer gets per ERC1363 token.
   */
  function rate() public view returns (uint256) {
    return _rate;
  }

  /**
   * @return the amount of ERC1363 token raised.
   */
  function tokenRaised() public view returns (uint256) {
    return _tokenRaised;
  }

  /**
   * @dev This method is called after `onTransferReceived`.
   *  Note: remember that the token contract address is always the message sender.
   * @param operator The address which called `transferAndCall` or `transferFromAndCall` function
   * @param sender Address performing the token purchase
   * @param amount The amount of tokens transferred
   * @param data Additional data with no specified format
   */
  function _transferReceived(
    address operator,
    address sender,
    uint256 amount,
    bytes memory data
  ) internal override {
    _buyTokens(operator, sender, amount, data);
  }

  /**
   * @dev This method is called after `onApprovalReceived`.
   *  Note: remember that the token contract address is always the message sender.
   * @param sender address The address which called `approveAndCall` function
   * @param amount uint256 The amount of tokens to be spent
   * @param data bytes Additional data with no specified format
   */
  function _approvalReceived(
    address sender,
    uint256 amount,
    bytes memory data
  ) internal override {
    IERC20(acceptedToken()).transferFrom(sender, address(this), amount);
    _buyTokens(sender, sender, amount, data);
  }

  /**
   * @dev low level token purchase ***DO NOT OVERRIDE***
   * This function has a non-reentrancy guard, so it shouldn't be called by
   * another `nonReentrant` function.
   * @param operator The address which called `transferAndCall`, `transferFromAndCall` or `approveAndCall` function
   * @param sender Address performing the token purchase
   * @param amount The amount of tokens transferred
   * @param data Additional data with no specified format
   */
  function _buyTokens(
    address operator,
    address sender,
    uint256 amount,
    bytes memory data
  ) internal nonReentrant {
    uint256 sentTokenAmount = amount;
    _preValidatePurchase(sentTokenAmount);

    // calculate token amount to be created
    uint256 tokens = _getTokenAmount(sentTokenAmount);

    // update state
    _tokenRaised += sentTokenAmount;

    _processPurchase(sender, tokens);
    emit TokensPurchased(operator, sender, sentTokenAmount, tokens);

    _updatePurchasingState(sender, sentTokenAmount, data);

    _forwardFunds(sentTokenAmount);
    _postValidatePurchase(sender, sentTokenAmount);
  }

  /**
   * @dev Validation of an incoming purchase.
   * Use require statements to revert state when conditions are not met.
   * Use `super` in contracts that inherit from ERC1363PayableCrowdsale to extend their validations.
   * @param sentTokenAmount Value in ERC1363 tokens involved in the purchase
   */
  function _preValidatePurchase(uint256 sentTokenAmount) internal pure {
    require(sentTokenAmount != 0);
  }

  /**
   * @dev Validation of an executed purchase.
   * Observe state and use revert statements to undo rollback when valid conditions are not met.
   * @param beneficiary Address performing the token purchase
   * @param sentTokenAmount Value in ERC1363 tokens involved in the purchase
   */
  function _postValidatePurchase(address beneficiary, uint256 sentTokenAmount)
    internal
  {
    // optional override
  }

  /**
   * @dev Source of tokens.
   * Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
   * @param beneficiary Address performing the token purchase
   * @param tokenAmount Number of tokens to be emitted
   */
  function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
    _token.safeTransfer(beneficiary, tokenAmount);
  }

  /**
   * @dev Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
   * @param beneficiary Address receiving the tokens
   * @param tokenAmount Number of tokens to be purchased
   */
  function _processPurchase(address beneficiary, uint256 tokenAmount) internal {
    _deliverTokens(beneficiary, tokenAmount);
  }

  /**
   * @dev Override for extensions that require an internal state to check for validity
   * @param beneficiary Address receiving the tokens
   * @param sentTokenAmount Value in ERC1363 tokens involved in the purchase
   * @param data Additional data with no specified format (Maybe a referral code)
   */
  function _updatePurchasingState(
    address beneficiary,
    uint256 sentTokenAmount,
    bytes memory data
  ) internal {
    // optional override
  }

  /**
   * @dev Override to extend the way in which ERC1363 tokens are converted to tokens.
   * @param sentTokenAmount Value in ERC1363 tokens to be converted into tokens
   * @return Number of tokens that can be purchased with the specified _sentTokenAmount
   */
  function _getTokenAmount(uint256 sentTokenAmount)
    internal
    view
    returns (uint256)
  {
    return sentTokenAmount * _rate;
  }

  /**
   * @dev Determines how ERC1363 tokens are stored/forwarded on purchases.
   * @param sentTokenAmount Value in ERC1363 tokens involved in the purchase
   */
  function _forwardFunds(uint256 sentTokenAmount) internal {
    IERC20(acceptedToken()).safeTransfer(_wallet, sentTokenAmount);
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
  using Address for address;

  function safeTransfer(
    IERC20 token,
    address to,
    uint256 value
  ) internal {
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.transfer.selector, to, value)
    );
  }

  function safeTransferFrom(
    IERC20 token,
    address from,
    address to,
    uint256 value
  ) internal {
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
    );
  }

  /**
   * @dev Deprecated. This function has issues similar to the ones found in
   * {IERC20-approve}, and its usage is discouraged.
   *
   * Whenever possible, use {safeIncreaseAllowance} and
   * {safeDecreaseAllowance} instead.
   */
  function safeApprove(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    // safeApprove should only be called when setting an initial allowance,
    // or when resetting it to zero. To increase and decrease it, use
    // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
    require(
      (value == 0) || (token.allowance(address(this), spender) == 0),
      "SafeERC20: approve from non-zero to non-zero allowance"
    );
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, value)
    );
  }

  function safeIncreaseAllowance(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    uint256 newAllowance = token.allowance(address(this), spender) + value;
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
    );
  }

  function safeDecreaseAllowance(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    unchecked {
      uint256 oldAllowance = token.allowance(address(this), spender);
      require(
        oldAllowance >= value,
        "SafeERC20: decreased allowance below zero"
      );
      uint256 newAllowance = oldAllowance - value;
      _callOptionalReturn(
        token,
        abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
      );
    }
  }

  /**
   * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
   * on the return value: the return value is optional (but if data is returned, it must not be false).
   * @param token The token targeted by the call.
   * @param data The call data (encoded using abi.encode or one of its variants).
   */
  function _callOptionalReturn(IERC20 token, bytes memory data) private {
    // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
    // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
    // the target address contains contract code and also asserts for success in the low-level call.

    bytes memory returndata = address(token).functionCall(
      data,
      "SafeERC20: low-level call failed"
    );
    if (returndata.length > 0) {
      // Return data is optional
      require(
        abi.decode(returndata, (bool)),
        "SafeERC20: ERC20 operation did not succeed"
      );
    }
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;

  uint256 private _status;

  constructor() {
    _status = _NOT_ENTERED;
  }

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and making it call a
   * `private` function that does the actual work.
   */
  modifier nonReentrant() {
    // On the first call to nonReentrant, _notEntered will be true
    require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

    // Any calls to nonReentrant after this point will fail
    _status = _ENTERED;

    _;

    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    _status = _NOT_ENTERED;
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/introspection/ERC165.sol";
import "../utils/introspection/ERC165Checker.sol";
import "../utils/Context.sol";

import "../token/ERC1363/IERC1363.sol";
import "../token/ERC1363/IERC1363Receiver.sol";
import "../token/ERC1363/IERC1363Spender.sol";

/**
 * @title ERC1363Payable
 * @author Vittorio Minacori (https://github.com/vittominacori)
 * @dev Implementation proposal of a contract that wants to accept ERC1363 payments
 */
contract ERC1363Payable is IERC1363Receiver, IERC1363Spender, ERC165, Context {
  using ERC165Checker for address;

  /**
   * @dev Emitted when `amount` tokens are moved from one account (`sender`) to
   * this by operator (`operator`) using {transferAndCall} or {transferFromAndCall}.
   */
  event TokensReceived(
    address indexed operator,
    address indexed sender,
    uint256 amount,
    bytes data
  );

  /**
   * @dev Emitted when the allowance of this for a `sender` is set by
   * a call to {approveAndCall}. `amount` is the new allowance.
   */
  event TokensApproved(address indexed sender, uint256 amount, bytes data);

  // The ERC1363 token accepted
  IERC1363 private _acceptedToken;

  /**
   * @param acceptedToken_ Address of the token being accepted
   */
  constructor(IERC1363 acceptedToken_) {
    require(
      address(acceptedToken_) != address(0),
      "ERC1363Payable: acceptedToken is zero address"
    );
    require(acceptedToken_.supportsInterface(type(IERC1363).interfaceId));

    _acceptedToken = acceptedToken_;
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC165)
    returns (bool)
  {
    return
      interfaceId == type(IERC1363Receiver).interfaceId ||
      interfaceId == type(IERC1363Spender).interfaceId ||
      super.supportsInterface(interfaceId);
  }

  /*
   * @dev Note: remember that the token contract address is always the message sender.
   * @param operator The address which called `transferAndCall` or `transferFromAndCall` function
   * @param sender The address which are token transferred from
   * @param amount The amount of tokens transferred
   * @param data Additional data with no specified format
   */
  function onTransferReceived(
    address operator,
    address sender,
    uint256 amount,
    bytes memory data
  ) public override returns (bytes4) {
    require(
      _msgSender() == address(_acceptedToken),
      "ERC1363Payable: acceptedToken is not message sender"
    );

    emit TokensReceived(operator, sender, amount, data);

    _transferReceived(operator, sender, amount, data);

    return IERC1363Receiver(this).onTransferReceived.selector;
  }

  /*
   * @dev Note: remember that the token contract address is always the message sender.
   * @param sender The address which called `approveAndCall` function
   * @param amount The amount of tokens to be spent
   * @param data Additional data with no specified format
   */
  function onApprovalReceived(
    address sender,
    uint256 amount,
    bytes memory data
  ) public override returns (bytes4) {
    require(
      _msgSender() == address(_acceptedToken),
      "ERC1363Payable: acceptedToken is not message sender"
    );

    emit TokensApproved(sender, amount, data);

    _approvalReceived(sender, amount, data);

    return IERC1363Spender(this).onApprovalReceived.selector;
  }

  /**
   * @dev The ERC1363 token accepted
   */
  function acceptedToken() public view returns (IERC1363) {
    return _acceptedToken;
  }

  /**
   * @dev Called after validating a `onTransferReceived`. Override this method to
   * make your stuffs within your contract.
   * @param operator The address which called `transferAndCall` or `transferFromAndCall` function
   * @param sender The address which are token transferred from
   * @param amount The amount of tokens transferred
   * @param data Additional data with no specified format
   */
  function _transferReceived(
    address operator,
    address sender,
    uint256 amount,
    bytes memory data
  ) internal virtual {
    // optional override
  }

  /**
   * @dev Called after validating a `onApprovalReceived`. Override this method to
   * make your stuffs within your contract.
   * @param sender The address which called `approveAndCall` function
   * @param amount The amount of tokens to be spent
   * @param data Additional data with no specified format
   */
  function _approvalReceived(
    address sender,
    uint256 amount,
    bytes memory data
  ) internal virtual {
    // optional override
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
  /**
   * @dev Returns the amount of tokens in existence.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns the amount of tokens owned by `account`.
   */
  function balanceOf(address account) external view returns (uint256);

  /**
   * @dev Moves `amount` tokens from the caller's account to `recipient`.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transfer(address recipient, uint256 amount) external returns (bool);

  /**
   * @dev Returns the remaining number of tokens that `spender` will be
   * allowed to spend on behalf of `owner` through {transferFrom}. This is
   * zero by default.
   *
   * This value changes when {approve} or {transferFrom} are called.
   */
  function allowance(address owner, address spender)
    external
    view
    returns (uint256);

  /**
   * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
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
  function approve(address spender, uint256 amount) external returns (bool);

  /**
   * @dev Moves `amount` tokens from `sender` to `recipient` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

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
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
  /**
   * @dev Returns true if `account` is a contract.
   *
   * [IMPORTANT]
   * ====
   * It is unsafe to assume that an address for which this function returns
   * false is an externally-owned account (EOA) and not a contract.
   *
   * Among others, `isContract` will return false for the following
   * types of addresses:
   *
   *  - an externally-owned account
   *  - a contract in construction
   *  - an address where a contract will be created
   *  - an address where a contract lived, but was destroyed
   * ====
   */
  function isContract(address account) internal view returns (bool) {
    // This method relies on extcodesize, which returns 0 for contracts in
    // construction, since the code is only stored at the end of the
    // constructor execution.

    uint256 size;
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }

  /**
   * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
   * `recipient`, forwarding all available gas and reverting on errors.
   *
   * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
   * of certain opcodes, possibly making contracts go over the 2300 gas limit
   * imposed by `transfer`, making them unable to receive funds via
   * `transfer`. {sendValue} removes this limitation.
   *
   * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
   *
   * IMPORTANT: because control is transferred to `recipient`, care must be
   * taken to not create reentrancy vulnerabilities. Consider using
   * {ReentrancyGuard} or the
   * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
   */
  function sendValue(address payable recipient, uint256 amount) internal {
    require(address(this).balance >= amount, "Address: insufficient balance");

    (bool success, ) = recipient.call{value: amount}("");
    require(
      success,
      "Address: unable to send value, recipient may have reverted"
    );
  }

  /**
   * @dev Performs a Solidity function call using a low level `call`. A
   * plain `call` is an unsafe replacement for a function call: use this
   * function instead.
   *
   * If `target` reverts with a revert reason, it is bubbled up by this
   * function (like regular Solidity function calls).
   *
   * Returns the raw returned data. To convert to the expected return value,
   * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
   *
   * Requirements:
   *
   * - `target` must be a contract.
   * - calling `target` with `data` must not revert.
   *
   * _Available since v3.1._
   */
  function functionCall(address target, bytes memory data)
    internal
    returns (bytes memory)
  {
    return functionCall(target, data, "Address: low-level call failed");
  }

  /**
   * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
   * `errorMessage` as a fallback revert reason when `target` reverts.
   *
   * _Available since v3.1._
   */
  function functionCall(
    address target,
    bytes memory data,
    string memory errorMessage
  ) internal returns (bytes memory) {
    return functionCallWithValue(target, data, 0, errorMessage);
  }

  /**
   * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
   * but also transferring `value` wei to `target`.
   *
   * Requirements:
   *
   * - the calling contract must have an ETH balance of at least `value`.
   * - the called Solidity function must be `payable`.
   *
   * _Available since v3.1._
   */
  function functionCallWithValue(
    address target,
    bytes memory data,
    uint256 value
  ) internal returns (bytes memory) {
    return
      functionCallWithValue(
        target,
        data,
        value,
        "Address: low-level call with value failed"
      );
  }

  /**
   * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
   * with `errorMessage` as a fallback revert reason when `target` reverts.
   *
   * _Available since v3.1._
   */
  function functionCallWithValue(
    address target,
    bytes memory data,
    uint256 value,
    string memory errorMessage
  ) internal returns (bytes memory) {
    require(
      address(this).balance >= value,
      "Address: insufficient balance for call"
    );
    require(isContract(target), "Address: call to non-contract");

    (bool success, bytes memory returndata) = target.call{value: value}(data);
    return verifyCallResult(success, returndata, errorMessage);
  }

  /**
   * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
   * but performing a static call.
   *
   * _Available since v3.3._
   */
  function functionStaticCall(address target, bytes memory data)
    internal
    view
    returns (bytes memory)
  {
    return
      functionStaticCall(target, data, "Address: low-level static call failed");
  }

  /**
   * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
   * but performing a static call.
   *
   * _Available since v3.3._
   */
  function functionStaticCall(
    address target,
    bytes memory data,
    string memory errorMessage
  ) internal view returns (bytes memory) {
    require(isContract(target), "Address: static call to non-contract");

    (bool success, bytes memory returndata) = target.staticcall(data);
    return verifyCallResult(success, returndata, errorMessage);
  }

  /**
   * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
   * but performing a delegate call.
   *
   * _Available since v3.4._
   */
  function functionDelegateCall(address target, bytes memory data)
    internal
    returns (bytes memory)
  {
    return
      functionDelegateCall(
        target,
        data,
        "Address: low-level delegate call failed"
      );
  }

  /**
   * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
   * but performing a delegate call.
   *
   * _Available since v3.4._
   */
  function functionDelegateCall(
    address target,
    bytes memory data,
    string memory errorMessage
  ) internal returns (bytes memory) {
    require(isContract(target), "Address: delegate call to non-contract");

    (bool success, bytes memory returndata) = target.delegatecall(data);
    return verifyCallResult(success, returndata, errorMessage);
  }

  /**
   * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
   * revert reason using the provided one.
   *
   * _Available since v4.3._
   */
  function verifyCallResult(
    bool success,
    bytes memory returndata,
    string memory errorMessage
  ) internal pure returns (bytes memory) {
    if (success) {
      return returndata;
    } else {
      // Look for revert reason and bubble it up if present
      if (returndata.length > 0) {
        // The easiest way to bubble the revert reason is using memory via assembly

        assembly {
          let returndata_size := mload(returndata)
          revert(add(32, returndata), returndata_size)
        }
      } else {
        revert(errorMessage);
      }
    }
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override
    returns (bool)
  {
    return interfaceId == type(IERC165).interfaceId;
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Library used to query support of an interface declared via {IERC165}.
 *
 * Note that these functions return the actual result of the query: they do not
 * `revert` if an interface is not supported. It is up to the caller to decide
 * what to do in these cases.
 */
library ERC165Checker {
  // As per the EIP-165 spec, no interface should ever match 0xffffffff
  bytes4 private constant _INTERFACE_ID_INVALID = 0xffffffff;

  /**
   * @dev Returns true if `account` supports the {IERC165} interface,
   */
  function supportsERC165(address account) internal view returns (bool) {
    // Any contract that implements ERC165 must explicitly indicate support of
    // InterfaceId_ERC165 and explicitly indicate non-support of InterfaceId_Invalid
    return
      _supportsERC165Interface(account, type(IERC165).interfaceId) &&
      !_supportsERC165Interface(account, _INTERFACE_ID_INVALID);
  }

  /**
   * @dev Returns true if `account` supports the interface defined by
   * `interfaceId`. Support for {IERC165} itself is queried automatically.
   *
   * See {IERC165-supportsInterface}.
   */
  function supportsInterface(address account, bytes4 interfaceId)
    internal
    view
    returns (bool)
  {
    // query support of both ERC165 as per the spec and support of _interfaceId
    return
      supportsERC165(account) && _supportsERC165Interface(account, interfaceId);
  }

  /**
   * @dev Returns a boolean array where each value corresponds to the
   * interfaces passed in and whether they're supported or not. This allows
   * you to batch check interfaces for a contract where your expectation
   * is that some interfaces may not be supported.
   *
   * See {IERC165-supportsInterface}.
   *
   * _Available since v3.4._
   */
  function getSupportedInterfaces(address account, bytes4[] memory interfaceIds)
    internal
    view
    returns (bool[] memory)
  {
    // an array of booleans corresponding to interfaceIds and whether they're supported or not
    bool[] memory interfaceIdsSupported = new bool[](interfaceIds.length);

    // query support of ERC165 itself
    if (supportsERC165(account)) {
      // query support of each interface in interfaceIds
      for (uint256 i = 0; i < interfaceIds.length; i++) {
        interfaceIdsSupported[i] = _supportsERC165Interface(
          account,
          interfaceIds[i]
        );
      }
    }

    return interfaceIdsSupported;
  }

  /**
   * @dev Returns true if `account` supports all the interfaces defined in
   * `interfaceIds`. Support for {IERC165} itself is queried automatically.
   *
   * Batch-querying can lead to gas savings by skipping repeated checks for
   * {IERC165} support.
   *
   * See {IERC165-supportsInterface}.
   */
  function supportsAllInterfaces(address account, bytes4[] memory interfaceIds)
    internal
    view
    returns (bool)
  {
    // query support of ERC165 itself
    if (!supportsERC165(account)) {
      return false;
    }

    // query support of each interface in _interfaceIds
    for (uint256 i = 0; i < interfaceIds.length; i++) {
      if (!_supportsERC165Interface(account, interfaceIds[i])) {
        return false;
      }
    }

    // all interfaces supported
    return true;
  }

  /**
   * @notice Query if a contract implements an interface, does not check ERC165 support
   * @param account The address of the contract to query for support of an interface
   * @param interfaceId The interface identifier, as specified in ERC-165
   * @return true if the contract at account indicates support of the interface with
   * identifier interfaceId, false otherwise
   * @dev Assumes that account contains a contract that supports ERC165, otherwise
   * the behavior of this method is undefined. This precondition can be checked
   * with {supportsERC165}.
   * Interface identification is specified in ERC-165.
   */
  function _supportsERC165Interface(address account, bytes4 interfaceId)
    private
    view
    returns (bool)
  {
    bytes memory encodedParams = abi.encodeWithSelector(
      IERC165.supportsInterface.selector,
      interfaceId
    );
    (bool success, bytes memory result) = account.staticcall{gas: 30000}(
      encodedParams
    );
    if (result.length < 32) return false;
    return success && abi.decode(result, (bool));
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC20/interfaces/IERC20.sol";
import "../../utils/introspection/IERC165.sol";

interface IERC1363 is IERC20, IERC165 {

  function transferAndCall(address recipient, uint256 amount)
    external
    returns (bool);


  function transferAndCall(
    address recipient,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);


  function transferFromAndCall(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);


  function transferFromAndCall(
    address sender,
    address recipient,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);


  function approveAndCall(address spender, uint256 amount)
    external
    returns (bool);

  
  function approveAndCall(
    address spender,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IERC1363Receiver Interface
 * @author Vittorio Minacori (https://github.com/vittominacori)
 * @dev Interface for any contract that wants to support transferAndCall or transferFromAndCall
 *  from ERC1363 token contracts as defined in
 *  https://eips.ethereum.org/EIPS/eip-1363
 */
interface IERC1363Receiver {
  /**
   * @notice Handle the receipt of ERC1363 tokens
   * @dev Any ERC1363 smart contract calls this function on the recipient
   * after a `transfer` or a `transferFrom`. This function MAY throw to revert and reject the
   * transfer. Return of other than the magic value MUST result in the
   * transaction being reverted.
   * Note: the token contract address is always the message sender.
   * @param operator address The address which called `transferAndCall` or `transferFromAndCall` function
   * @param sender address The address which are token transferred from
   * @param amount uint256 The amount of tokens transferred
   * @param data bytes Additional data with no specified format
   * @return `bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"))` unless throwing
   */
  function onTransferReceived(
    address operator,
    address sender,
    uint256 amount,
    bytes calldata data
  ) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IERC1363Spender Interface
 * @author Vittorio Minacori (https://github.com/vittominacori)
 * @dev Interface for any contract that wants to support approveAndCall
 *  from ERC1363 token contracts as defined in
 *  https://eips.ethereum.org/EIPS/eip-1363
 */
interface IERC1363Spender {
  /**
   * @notice Handle the approval of ERC1363 tokens
   * @dev Any ERC1363 smart contract calls this function on the recipient
   * after an `approve`. This function MAY throw to revert and reject the
   * approval. Return of other than the magic value MUST result in the
   * transaction being reverted.
   * Note: the token contract address is always the message sender.
   * @param sender address The address which called `approveAndCall` function
   * @param amount uint256 The amount of tokens to be spent
   * @param data bytes Additional data with no specified format
   * @return `bytes4(keccak256("onApprovalReceived(address,uint256,bytes)"))` unless throwing
   */
  function onApprovalReceived(
    address sender,
    uint256 amount,
    bytes calldata data
  ) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
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
   * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
   * to learn more about how these ids are created.
   *
   * This function call must use less than 30 000 gas.
   */
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

{
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "devdoc",
        "userdoc",
        "metadata",
        "abi"
      ]
    }
  },
  "libraries": {}
}