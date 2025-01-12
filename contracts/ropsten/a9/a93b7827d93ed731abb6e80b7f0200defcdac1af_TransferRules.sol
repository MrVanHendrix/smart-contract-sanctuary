/**
 *Submitted for verification at Etherscan.io on 2021-03-02
*/

// File: node_modules\@openzeppelin\contracts-upgradeable\utils\AddressUpgradeable.sol

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
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

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
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
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
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

// File: node_modules\@openzeppelin\contracts-upgradeable\proxy\Initializable.sol



// solhint-disable-next-line compiler-version
pragma solidity >=0.4.24 <0.8.0;


/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {UpgradeableProxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {

    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /// @dev Returns true if and only if the function is running in the constructor
    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}

// File: node_modules\@openzeppelin\contracts-upgradeable\utils\ContextUpgradeable.sol



pragma solidity >=0.6.0 <0.8.0;


/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
}

// File: @openzeppelin\contracts-upgradeable\access\OwnableUpgradeable.sol



pragma solidity >=0.6.0 <0.8.0;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
    uint256[49] private __gap;
}

// File: @openzeppelin\contracts-upgradeable\utils\EnumerableSetUpgradeable.sol



pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSetUpgradeable {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

// File: @openzeppelin\contracts-upgradeable\math\SafeMathUpgradeable.sol



pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMathUpgradeable {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

// File: @openzeppelin\contracts-upgradeable\math\MathUpgradeable.sol



pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library MathUpgradeable {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}

// File: contracts\interfaces\ISRC20.sol


pragma solidity >=0.6.0 <0.8.0;
/**
 * @title SRC20 public interface
 */
interface ISRC20 {
    function balanceOf(address who) external view returns (uint256);
    function executeTransfer(address from, address to, uint256 value) external returns (bool);
}

// File: contracts\interfaces\ITransferRules.sol


pragma solidity >=0.6.0 <0.8.0;
/**
 * @title ITransferRules interface
 * @dev Represents interface for any on-chain SRC20 transfer rules
 * implementation. Transfer Rules are expected to follow
 * same interface, managing multiply transfer rule implementations with
 * capabilities of managing what happens with tokens.
 *
 * This interface is working with ERC20 transfer() function
 */
interface ITransferRules {
    function setSRC(address src20) external returns (bool);
    function doTransfer(address from, address to, uint256 value) external returns (bool);
}

// File: contracts\Whitelist.sol



pragma solidity >=0.6.0 <0.8.0;



/**
 * Realization a addresses whitelist
 * 
 */
contract Whitelist is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    
    struct List {
        address addr;
        bool alsoGradual;
    }
    struct ListStruct {
        EnumerableSetUpgradeable.AddressSet indexes;
        mapping(address => List) data;
    }
    
    string internal commonGroupName;
    
    mapping(string => ListStruct) list;

    modifier onlyWhitelist(string memory groupName) {
        require(
            list[groupName].indexes.contains(_msgSender()) == true, 
            "Sender is not in whitelist"
        );
        _;
    }
   
    function __Whitelist_init(
    )
        internal 
        initializer 
    {
        commonGroupName = 'common';
        __Ownable_init();
    }
    
    
    /**
     * Adding addresses list to whitelist 
     * 
     * @dev available to Owner only
     * Requirements:
     *
     * - `_addresses` cannot contains the zero address.
     * 
     * @param _addresses list of addresses which will be added to whitelist
     * @return success return true in any cases
     */
    function whitelistAdd(address[] memory _addresses) public virtual returns (bool success) {
        success = _whitelistAdd(commonGroupName, _addresses);
    }
    
    /**
     * Removing addresses list from whitelist
     * 
     * @dev Available to Owner only
     * Requirements:
     *
     * - `_addresses` cannot contains the zero address.
     * 
     * @param _addresses list of addresses which will be removed from whitelist
     * @return success return true in any cases 
     */
    function whitelistRemove(address[] memory _addresses) public virtual returns (bool success) {
        success = _whitelistRemove(commonGroupName, _addresses);
    }

    /**
    * Checks if a address already exists in a whitelist
    * 
    * @param addr address
    * @return result return true if exist 
    */
    function isWhitelisted(address addr) public virtual view returns (bool result) {
        result = _isWhitelisted(commonGroupName, addr);
    }
    
    
    function _whitelistAdd(string memory groupName, address[] memory _addresses) internal returns (bool) {
        for (uint i = 0; i < _addresses.length; i++) {
            require(_addresses[i] != address(0), "Whitelist: Contains the zero address");
            
            if (list[groupName].indexes.contains(_addresses[i]) == true) {
                // already exist
            } else {
                list[groupName].indexes.add(_addresses[i]);
                list[groupName].data[_addresses[i]].addr = _addresses[i];
            }
        }
        return true;
    }
    
    function _whitelistRemove(string memory groupName, address[] memory _addresses) internal returns (bool) {
        for (uint i = 0; i < _addresses.length; i++) {
            if (list[groupName].indexes.remove(_addresses[i]) == true) {
                delete list[groupName].data[_addresses[i]];
            }
        }
        return true;
    }
    
    function _isWhitelisted(string memory groupName, address addr) internal view returns (bool) {
        return list[groupName].indexes.contains(addr);
    }
  
}

// File: contracts\interfaces\IIntercoin.sol


pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

interface IIntercoin {
    
    function registerInstance(address addr) external returns(bool);
    function checkInstance(address addr) external view returns(bool);
    
}

// File: contracts\interfaces\IIntercoinTrait.sol


pragma solidity >=0.6.0 <0.8.0;

interface IIntercoinTrait {
    
    function setIntercoinAddress(address addr) external returns(bool);
    function getIntercoinAddress() external view returns (address);
    
}

// File: contracts\IntercoinTrait.sol


pragma solidity >=0.7.0 <0.8.0;




contract IntercoinTrait is Initializable, IIntercoinTrait {
    
    address private intercoinAddr;
    bool private isSetup;

    /**
     * setup intercoin contract's address. happens once while initialization through factory
     * @param addr address of intercoin contract
     */
    function setIntercoinAddress(address addr) public override returns(bool) {
        require (addr != address(0), 'Address can not be empty');
        require (isSetup == false, 'Already setup');
        intercoinAddr = addr;
        isSetup = true;
        
        return true;
    }
    
    /**
     * got stored intercoin address
     */
    function getIntercoinAddress() public override view returns (address) {
        return intercoinAddr;
    }
    
    /**
     * @param addr address of contract that need to be checked at intercoin contract
     */
    function checkInstance(address addr) internal view returns(bool) {
        require (intercoinAddr != address(0), 'Intercoin address need to be setup before');
        return IIntercoin(intercoinAddr).checkInstance(addr);
    }
}

// File: contracts\TransferRules.sol



pragma solidity >=0.7.0 <0.8.0;











/*
 * @title TransferRules contract
 * @dev Contract that is checking if on-chain rules for token transfers are concluded.
 */
contract TransferRules is Initializable, OwnableUpgradeable, ITransferRules, Whitelist, IntercoinTrait {

	ISRC20 public _src20;
	using SafeMathUpgradeable for uint256;
	using MathUpgradeable for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
	
    struct Lockup {
        uint256 duration;
        //bool gradual; // does not used 
        bool exists;
    }
    
    struct Minimum {
        uint256 timestampStart;
        uint256 timestampEnd;
        uint256 amount;
        bool gradual;
    }
    struct UserStruct {
        EnumerableSetUpgradeable.UintSet minimumsIndexes;
        mapping(uint256 => Minimum) minimums;
        Lockup lockup;
    }
    
    struct whitelistSettings {
        uint256 reducePeriod;
        //bool alsoGradual;// does not used 
        bool exists;
    }
    
    whitelistSettings settings;
    mapping (address => UserStruct) users;
    
    uint256 internal dayInSeconds;
    string  internal managersGroupName;
    
    modifier onlySRC20 {
        require(msg.sender == address(_src20));
        _;
    }
    
    //---------------------------------------------------------------------------------
    // public  section
    //---------------------------------------------------------------------------------

    /**
     * init method
     */
    function init(
    ) 
        public 
        initializer 
    {
        __TransferRules_init();
    }
    
    /**
    * @dev clean SRC20. available only for owner
    */
    function cleanSRC(
    ) 
        public
        onlyOwner()
    {
        _src20 = ISRC20(address(0));
    }
    
    
    /**
    * @dev viewing minimum holding in sender during period from now to timestamp.
    */
    function minimumsView(
    ) 
        public
        view
        returns (uint256)
    {
        return getMinimum(_msgSender());
    }
    
    /**
    * @dev adding minimum holding at sender during period from now to timestamp.
    *
    * @param addr address which should be restricted
    * @param amount amount.
    * @param timestamp period until minimum applied
    * @param gradual true if the limitation can gradually decrease
    */
    function minimumsAdd(
        address addr,
        uint256 amount, 
        uint256 timestamp,
        bool gradual
    ) 
        public
        onlyOwner()
        returns (bool)
    {
        require(timestamp > block.timestamp, 'timestamp is less then current block.timestamp');
        
        _minimumsClear(addr, false);
        require(users[addr].minimumsIndexes.add(timestamp), 'minimum already exist');
        
        //users[addr].data[timestamp] = minimum;
        users[addr].minimums[timestamp].timestampStart = block.timestamp;
        users[addr].minimums[timestamp].timestampEnd = timestamp;
        users[addr].minimums[timestamp].amount = amount;
        users[addr].minimums[timestamp].gradual = gradual;
        return true;
        
    }
    
    /**
     * @dev removes all minimums from this address
     * so all tokens are unlocked to send
     * @param addr address which should be clear restrict
     */
    function minimumsClear(
        address addr
    )
        public 
        onlyOwner()
        returns (bool)
    {
        return _minimumsClear(addr, true);
    }
        
 
    /**
    * @dev Checks if transfer passes transfer rules.
    *
    * @param from The address to transfer from.
    * @param to The address to send tokens to.
    * @param value The amount of tokens to send.
    */
    function authorize(
        address from, 
        address to, 
        uint256 value
    ) 
        public 
        view
        returns (bool) 
    {
        uint256 balanceOfFrom = ISRC20(_src20).balanceOf(from);
        return _authorize(from, to, value, balanceOfFrom);
    }
    
    /**
     * added managers. available only for owner
     * @param addresses array of manager's addreses
     */
    function managersAdd(
        address[] memory addresses
    )
        public 
        onlyOwner
        returns(bool)
    {
        return _whitelistAdd(managersGroupName, addresses);
    }     
    
    /**
     * removed managers. available only for owner
     * @param addresses array of manager's addreses
     */
    function managersRemove(
        address[] memory addresses
    )
        public 
        onlyOwner
        returns(bool)
    {
        return _whitelistRemove(managersGroupName, addresses);
    }    
    
    /**
     * Adding addresses list to whitelist
     * 
     * @dev Available from whitelist with group 'managers'(managersGroupName) only
     * 
     * @param addresses list of addresses which will be added to whitelist
     * @return success return true in any cases 
     */
    function whitelistAdd(
        address[] memory addresses
    )
        public 
        override 
        onlyWhitelist(managersGroupName) 
        returns (bool success) 
    {
        success = _whitelistAdd(commonGroupName, addresses);
    }
    
    /**
     * Removing addresses list from whitelist
     * 
     * @dev Available from whitelist with group 'managers'(managersGroupName) only
     * Requirements:
     *
     * - `addresses` cannot contains the zero address.
     * 
     * @param addresses list of addresses which will be removed from whitelist
     * @return success return true in any cases 
     */
    function whitelistRemove(
        address[] memory addresses
    ) 
        public 
        override 
        onlyWhitelist(managersGroupName) 
        returns (bool success) 
    {
        success = _whitelistRemove(commonGroupName, addresses);
    }
    
    /**
     * @param from will add automatic lockup for destination address sent address from
     * @param daysAmount duration in days
     */
    function automaticLockupAdd(
        address from,
        uint256 daysAmount
    )
        public 
        onlyOwner()
    {
        users[from].lockup.duration = daysAmount.mul(dayInSeconds);
        users[from].lockup.exists = true;
    }
    
    /**
     * @param from remove automaticLockup from address 
     */
    function automaticLockupRemove(
        address from
    )
        public 
        onlyOwner()
    {
        users[from].lockup.exists = false;
    }
    
    
    /**
     * @dev whenever anyone on whitelist receives tokens their lockup time reduce to daysAmount(if less)
     * @param daysAmount duration in days. if equal 0 then reduce mechanizm are removed
     */
    function whitelistReduce(
        uint256 daysAmount
    )
        public 
        onlyOwner()
    {
        if (daysAmount == 0) {
            settings.exists = false;    
        } else {
            settings.reducePeriod = daysAmount.mul(dayInSeconds);
            settings.exists = true;    
        }
        
    }

    //---------------------------------------------------------------------------------
    // internal  section
    //---------------------------------------------------------------------------------
    
    /**
     * init internal
     */
    function __TransferRules_init(
    ) 
        internal
        initializer 
    {
        __Ownable_init();
        __Whitelist_init();
        
        dayInSeconds = 86400;
        managersGroupName = 'managers';
    }
    
    /**
    * @param from The address to transfer from.
    * @param to The address to send tokens to.
    * @param value The amount of tokens to send.
    * @param balanceOfFrom balance at from before transfer
    */
    function _authorize(
        address from, 
        address to, 
        uint256 value,
        uint256 balanceOfFrom
    ) 
        internal
        view
        returns (bool) 
    {

        if (
            (balanceOfFrom >= value) && 
            (
                (isWhitelisted(to)) ||
                (getMinimum(from) <= balanceOfFrom.sub(value))
            )
            
        ) {
            return true;
        }
        return false;
    }
    
    

    /**
    * @dev get sum minimum from address for period from now to timestamp.
    *
    * @param addr address.
    */
    function getMinimum(
        address addr
    ) 
        internal 
        view
        returns (uint256 ret) 
    {
        ret = 0;
        
        uint256 iMinimum = 0;
        uint256 mapIndex = 0;
        
        for (uint256 i=0; i<users[addr].minimumsIndexes.length(); i++) {
            mapIndex = users[addr].minimumsIndexes.at(i);
            iMinimum = users[addr].minimums[mapIndex].amount;
            if (block.timestamp <= users[addr].minimums[mapIndex].timestampEnd) {
                if (users[addr].minimums[mapIndex].gradual == true) {
                    
                        iMinimum = iMinimum.div(
                                        users[addr].minimums[mapIndex].timestampEnd.sub(users[addr].minimums[mapIndex].timestampStart)
                                        ).
                                     mul(
                                        users[addr].minimums[mapIndex].timestampEnd.sub(block.timestamp)
                                        );
                       
                }
                
                ret = ret.add(iMinimum);
            }
        }
        
    }
    
    /**
    * @dev clear expired items from mapping. used while addingMinimum
    *
    * @param addr address.
    * @param deleteAnyway if true when delete items regardless expired or not
    */
    function _minimumsClear(
        address addr,
        bool deleteAnyway
    ) 
        internal 
        returns (bool) 
    {
        uint256 mapIndex = 0;
        uint256 len = users[addr].minimumsIndexes.length();
        if (len > 0) {
            for (uint256 i=len; i>0; i--) {
                mapIndex = users[addr].minimumsIndexes.at(i-1);
                if (
                    (deleteAnyway == true) ||
                    (block.timestamp > users[addr].minimums[mapIndex].timestampEnd)
                ) {
                    delete users[addr].minimums[mapIndex];
                    users[addr].minimumsIndexes.remove(mapIndex);
                }
                
            }
        }
        return true;
    }

    /**
     * added minimum if not exist by timestamp else append it
     * @param receiver destination address
     * @param timestampEnd "until time"
     * @param value amount
     * @param gradual if true then lockup are gradually
     */
    function _appendMinimum(
        address receiver,
        uint256 timestampEnd, 
        uint256 value, 
        bool gradual
    )
        internal
    {

        if (users[receiver].minimumsIndexes.add(timestampEnd) == true) {
            users[receiver].minimums[timestampEnd].timestampStart = block.timestamp;
            users[receiver].minimums[timestampEnd].amount = value;
            users[receiver].minimums[timestampEnd].timestampEnd = timestampEnd;
            users[receiver].minimums[timestampEnd].gradual = gradual; 
        } else {
            //'minimum already exist' 
            // just summ exist and new value
            users[receiver].minimums[timestampEnd].amount = users[receiver].minimums[timestampEnd].amount.add(value);
        }
    }
    
    /**
     * @dev reduce minimum by value  otherwise remove it 
     * @param addr destination address
     * @param timestampEnd "until time"
     * @param value amount
     */
    function _reduceMinimum(
        address addr,
        uint256 timestampEnd, 
        uint256 value
    )
        internal
    {
        
        if (users[addr].minimumsIndexes.contains(timestampEnd) == true) {
            if (value < users[addr].minimums[timestampEnd].amount) {
               users[addr].minimums[timestampEnd].amount = users[addr].minimums[timestampEnd].amount.sub(value);
            } else {
                delete users[addr].minimums[timestampEnd];
                users[addr].minimumsIndexes.remove(timestampEnd);
            }
        }
    }
    
    /**
     * @dev 
     *  A - issuers
     *  B - not on whitelist
     *  C - on whitelist
     *  There are rules:
     *  1. A sends to B: lockup for 1 year
     *  2. A sends to C: lock up for 40 days
     *  3. B sends to C: lock up for 40 days or remainder of B’s lockup, whichever is lower
     *  4. C sends to other C: transfer minimum with same timestamp to recipient and lockups must remove from sender
     * 
     * @param from sender address
     * @param to destination address
     * @param value amount
     * @param balanceFromBefore balances sender's address before executeTransfer
     */
    function applyRuleLockup(
        address from, 
        address to, 
        uint256 value,
        uint256 balanceFromBefore
    ) 
        internal
        onlySRC20
    {
        
        // check available balance for make transaction. in _authorize have already check whitelist(to) and available tokens 
        require(_authorize(from, to, value, balanceFromBefore), "Transfer not authorized");


        uint256 automaticLockupDuration;

        // get lockup time if was applied into fromAddress by automaticLockupAdd
        if (users[from].lockup.exists == true) {
            automaticLockupDuration = users[from].lockup.duration;
        }
        
        // calculate how much tokens we should transferMinimums without free tokens
        // here 
        //// value -- is how much tokens we would need to transfer
        //// minimum -- how much tokens locks
        //// balanceFromBefore-minimum -- it's free tokens
        //// value-(free tokens) -- how much tokens need to transferMinimums to destination address
        
        uint256 minimum = getMinimum(from);
        if (balanceFromBefore.sub(minimum) < value) {
            value = value.sub(balanceFromBefore.sub(minimum));    
        }
        
        // A -> B automaticLockup minimums added
        // A -> C automaticLockup minimums but reduce to 40
        // B -> C transferLockups and reduce to 40
        // C -> C transferLockups

        if (users[from].lockup.exists == true) {
            // then sender is A
            
            uint256 untilTimestamp = block.timestamp.add( 
                (isWhitelisted(to)) 
                ? 
                    (
                    settings.exists
                    ?
                    automaticLockupDuration.min(settings.reducePeriod) 
                    :
                    automaticLockupDuration
                    )
                : 
                automaticLockupDuration
                );
            
            _appendMinimum(
                to,
                untilTimestamp,
                value, 
                false   //bool gradual
            );
            
            // C -> C transferLockups
        } else if (isWhitelisted(from) && isWhitelisted(to)) {
            minimumsTransfer(
                from, 
                to, 
                value, 
                false, 
                0
            );
        } else{
            // else sender is B 
            
            if (isWhitelisted(to)) {
                minimumsTransfer(
                    from, 
                    to, 
                    value, 
                    true, 
                    block.timestamp.add(settings.reducePeriod)
                );
            }
            
            // else available only free tokens to transfer and this was checked in autorize method before
        }
    }
    
    /**
     * 
     * @param from sender address
     * @param to destination address
     * @param value amount
     * @param reduceTimeDiff if true then all timestamp which more then minTimeDiff will reduce to minTimeDiff
     * @param minTimeDiff minimum lockup timestamp time
     */
    function minimumsTransfer(
        address from, 
        address to, 
        uint256 value, 
        bool reduceTimeDiff,
        uint256 minTimeDiff
    )
        internal
    {
        
        uint256 len = users[from].minimumsIndexes.length();
        uint256[] memory _dataList;
        uint256 recieverTimeLeft;
        
        if (len > 0) {
            _dataList = new uint256[](len);
            for (uint256 i=0; i<len; i++) {
                _dataList[i] = users[from].minimumsIndexes.at(i);
            }
            _dataList = sortAsc(_dataList);
            
            uint256 iValue;
            
            
            for (uint256 i=0; i<len; i++) {
                
                
                if (value > users[from].minimums[_dataList[i]].amount) {
                    //iValue = users[from].data[_dataList[i]].minimum;
                    iValue = calculateAvailableMinimum(users[from].minimums[_dataList[i]]);
                    
                    value = value.sub(iValue);
                } else {
                    iValue = value;
                    value = 0;
                }
               
                recieverTimeLeft = users[from].minimums[_dataList[i]].timestampEnd.sub(block.timestamp);
                // put to reciver
                _appendMinimum(
                    to,
                    block.timestamp.add((reduceTimeDiff ? minTimeDiff.min(recieverTimeLeft) : recieverTimeLeft)),
                    iValue,
                    false //users[from].data[_dataList[i]].gradual
                );
                
                // remove from sender
                _reduceMinimum(
                    from,
                    users[from].minimums[_dataList[i]].timestampEnd,
                    iValue
                );
                  
                if (value == 0) {
                    break;
                }
            } // end for
            
            
            
            //!!!!!  value can not be left more then zero  if then minimums are gone
            // if (value != 0) {
                
            //     
            //     _appendMinimum(
            //         to,
            //         block.timestamp.add(durationLockupNoneUSAPerson),
            //         value,
            //         false
            //     );
            // }
            
        }
        
    }
    
    /**
     * @dev calculating limit funds for the moment 
     * if gradual option set to true then gradually 
     */
    function calculateAvailableMinimum(
        Minimum memory mininumStruct
    )
        internal
        view
        returns(uint256 ret)
    {
        if (mininumStruct.gradual == true) {
            if (block.timestamp >= mininumStruct.timestampEnd) {
                ret = (mininumStruct.amount).div(
                                        mininumStruct.timestampEnd.sub(mininumStruct.timestampStart)
                                        ).
                                     mul(
                                        mininumStruct.timestampEnd.sub(block.timestamp)
                                        );
            } else {
                ret = 0;
            }
                       
        } else {
            ret = mininumStruct.amount;
        }
    }
    
    //---------------------------------------------------------------------------------
    // external section
    //---------------------------------------------------------------------------------
    
    /**
    * @dev Set for what contract this rules are.
    *
    * @param src20 - Address of SRC20 contract.
    */
    function setSRC(
        address src20
    ) 
        override 
        external 
        returns (bool) 
    {
        require(address(_src20) == address(0), "SRC20 already set");
        _src20 = ISRC20(src20);
        return true;
    }

    /**
    * @dev Do transfer and checks where funds should go. If both from and to are
    * on the whitelist funds should be transferred but if one of them are on the
    * grey list token-issuer/owner need to approve transfer.
    *
    * @param from The address to transfer from.
    * @param to The address to send tokens to.
    * @param value The amount of tokens to send.
    */
    function doTransfer(
        address from, 
        address to, 
        uint256 value
    ) 
        override 
        external 
        onlySRC20 
        returns (bool) 
    {
        uint256 balanceFromBefore = ISRC20(_src20).balanceOf(from);
        require(ISRC20(_src20).executeTransfer(from, to, value), "SRC20 transfer failed");
        applyRuleLockup(from, to, value, balanceFromBefore);
        return true;
    }
    
    //---------------------------------------------------------------------------------
    // private  section
    //---------------------------------------------------------------------------------
    
    
    // useful method to sort native memory array 
    function sortAsc(uint256[] memory data) private returns(uint[] memory) {
       quickSortAsc(data, int(0), int(data.length - 1));
       return data;
    }
    
    function quickSortAsc(uint[] memory arr, int left, int right) private {
        int i = left;
        int j = right;
        if(i==j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSortAsc(arr, left, j);
        if (i < right)
            quickSortAsc(arr, i, right);
    }

	
}